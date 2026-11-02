import 'dart:convert';

import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

/// The exception for a failed pin call. A `404` becomes [PinNotFoundException];
/// a refusal whose error envelope has a code and a message becomes
/// [PinRefusedException], whose message is meant for the owner.
PinsException pinFailure(
  ApiResult result, {
  String notFoundMessage = 'Pin not found',
}) {
  switch (result) {
    case ApiPermanentFailure(statusCode: 404):
      return PinNotFoundException(notFoundMessage);
    case ApiPermanentFailure(
        statusCode: final code,
        message: final message,
        body: final body,
      ):
      final error = _errorOf(body);
      final refusedCode = error?['code'];
      final refusedMessage = error?['message'];
      if (refusedCode is String &&
          refusedMessage is String &&
          refusedMessage.isNotEmpty) {
        return PinRefusedException(refusedCode, refusedMessage);
      }
      return PinsGeneralException('Server error $code: $message');
    case ApiTransientFailure(reason: final reason):
      return PinsGeneralException(reason);
    case ApiNotConfigured():
      return PinsGeneralException('API not configured');
    case ApiSuccess():
      return PinsGeneralException('Unexpected success');
  }
}

Map<String, dynamic>? _errorOf(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;
    final error = json['error'];
    return error is Map<String, dynamic> ? error : null;
  } on FormatException {
    return null;
  }
}
