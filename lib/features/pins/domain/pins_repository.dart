import 'package:voice_agent/core/models/pin.dart';

/// List ordering for `GET /api/v1/pins?view=...`.
enum PinView {
  recent,
  topic;

  /// The `?view=` query value (`recent` | `topic`).
  String get queryValue => name;
}

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

abstract class PinsRepository {
  Future<List<PinSummary>> fetchPins(PinView view);
  Future<PinDetail> fetchPin(String recordId);
  Future<void> unpin(String recordId);
}
