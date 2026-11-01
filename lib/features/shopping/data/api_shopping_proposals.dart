import 'dart:convert';

import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';

/// `ApiClient`-backed [ShoppingProposalsPort] (personal-agent ADR-API-108).
class ApiShoppingProposals implements ShoppingProposalsPort {
  ApiShoppingProposals(this._apiClient);

  final ApiClient _apiClient;

  static const _path = '/shopping/proposals';

  @override
  Future<List<ShoppingProposal>> list({String? conversationId}) async {
    final result = await _apiClient.get(
      _path,
      queryParameters: conversationId == null
          ? {'state': 'waiting'}
          : {'conversation_id': conversationId},
    );
    return switch (result) {
      ApiSuccess(body: final body) => _proposals(body),
      ApiPermanentFailure(message: final msg, statusCode: final code) =>
        throw ShoppingProposalsException('Server error $code: $msg'),
      ApiTransientFailure(reason: final reason) =>
        throw ShoppingProposalsException(reason),
      ApiNotConfigured() =>
        throw ShoppingProposalsException('API not configured'),
    };
  }

  List<ShoppingProposal> _proposals(String? body) {
    try {
      final data = _envelope(body)?['data'] as List<dynamic>?;
      return (data ?? const [])
          .map((e) => ShoppingProposal.fromMap(e as Map<String, dynamic>))
          .toList();
    } on TypeError {
      throw ShoppingProposalsException('Unexpected response');
    } on FormatException {
      throw ShoppingProposalsException('Unexpected response');
    }
  }

  @override
  Future<ShoppingProposalAnswer> accept(String id) => _answer(id, 'accept');

  @override
  Future<ShoppingProposalAnswer> skip(String id) => _answer(id, 'skip');

  Future<ShoppingProposalAnswer> _answer(String id, String action) async {
    final result = await _apiClient.postJson(
      '$_path/${Uri.encodeComponent(id)}/$action',
    );
    try {
      return switch (result) {
        ApiSuccess(body: final body) => _answered(body),
        final ApiPermanentFailure failure when failure.statusCode == 409 =>
          _conflict(failure),
        ApiPermanentFailure(message: final msg, statusCode: final code) =>
          ProposalAnswerFailed('Server error $code: $msg'),
        ApiTransientFailure(reason: final reason) =>
          ProposalAnswerFailed(reason),
        ApiNotConfigured() => const ProposalAnswerFailed('API not configured'),
      };
    } on TypeError {
      return const ProposalAnswerFailed('Unexpected response');
    } on FormatException {
      return const ProposalAnswerFailed('Unexpected response');
    }
  }

  ShoppingProposalAnswer _answered(String? body) {
    final data = _envelope(body)?['data'] as Map<String, dynamic>;
    return ProposalAnswered(
      ShoppingProposal.fromMap(data['proposal'] as Map<String, dynamic>),
    );
  }

  ShoppingProposalAnswer _conflict(ApiPermanentFailure failure) {
    final envelope = _envelope(failure.body);
    final error = envelope?['error'] as Map<String, dynamic>?;
    switch (error?['code']) {
      case 'proposal_not_waiting':
        final data = envelope?['data'] as Map<String, dynamic>;
        return ProposalNotWaiting(data['state'] as String);
      case 'item_removed':
        return const ProposalItemRemoved();
      default:
        return ProposalAnswerFailed(
          'Server error ${failure.statusCode}: ${failure.message}',
        );
    }
  }

  Map<String, dynamic>? _envelope(String? body) =>
      body == null ? null : jsonDecode(body) as Map<String, dynamic>;
}
