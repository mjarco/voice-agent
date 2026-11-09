import 'package:voice_agent/core/models/pin.dart';

sealed class PinsException implements Exception {
  String get message;

  @override
  String toString() => message;
}

class PinsGeneralException extends PinsException {
  PinsGeneralException(this.message);
  @override
  final String message;
}

/// Pin does not exist or is already unpinned (backend 404).
class PinNotFoundException extends PinsException {
  PinNotFoundException([this.message = 'Pin not found']);
  @override
  final String message;
}

/// The server refused a write (`name_taken`, `pin_changed`, `text_too_large`,
/// `invalid_request`). [message] is the server's own, meant to be shown as it is.
class PinRefusedException extends PinsException {
  PinRefusedException(this.code, this.message);

  final String code;
  @override
  final String message;

  /// The write named an earlier version of the pin (ADR-CORE-111): what the
  /// client shows is out of date. personal-agent since R2 no longer sends it;
  /// kept for a server that does.
  bool get isStale => code == 'pin_changed';
}

abstract class PinsRepository {
  /// The pins, newest first.
  Future<List<PinSummary>> fetchPins();
  Future<PinDetail> fetchPin(String recordId);
  Future<void> unpin(String recordId);
}
