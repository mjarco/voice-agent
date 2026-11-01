import 'dart:async';

import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';

ShoppingProposal sampleProposal({
  String id = 'p1',
  String kind = 'add',
  String text = 'filtr do wody',
  String state = 'waiting',
  String? userEventId = 'ue-1',
}) =>
    ShoppingProposal(
      id: id,
      kind: kind,
      text: text,
      state: state,
      userEventId: userEventId,
    );

class FakeShoppingProposals implements ShoppingProposalsPort {
  List<ShoppingProposal> rows = [];
  bool failReads = false;

  /// Answers with this instead of the done proposal.
  ShoppingProposalAnswer? nextAnswer;

  /// Holds the answer back until it completes.
  Completer<void>? gate;

  /// Runs when an answer is given, to change what the next read returns.
  void Function()? onAnswer;

  String? lastConversationId;
  final List<String> accepted = [];
  final List<String> skipped = [];

  @override
  Future<List<ShoppingProposal>> list({String? conversationId}) async {
    lastConversationId = conversationId;
    if (failReads) throw ShoppingProposalsException('no route');
    return rows;
  }

  @override
  Future<ShoppingProposalAnswer> accept(String id) {
    accepted.add(id);
    return _answer(id, 'accepted');
  }

  @override
  Future<ShoppingProposalAnswer> skip(String id) {
    skipped.add(id);
    return _answer(id, 'skipped');
  }

  Future<ShoppingProposalAnswer> _answer(String id, String state) async {
    await gate?.future;
    onAnswer?.call();
    return nextAnswer ??
        ProposalAnswered(
          rows.firstWhere((p) => p.id == id, orElse: () => sampleProposal(id: id))
              .withState(state),
        );
  }
}
