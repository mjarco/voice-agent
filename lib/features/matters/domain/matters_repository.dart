import 'package:voice_agent/core/models/matter.dart';

sealed class MattersException implements Exception {
  String get message;

  @override
  String toString() => message;
}

class MattersGeneralException extends MattersException {
  MattersGeneralException(this.message);
  @override
  final String message;
}

/// The matter (or its entry or link) does not exist (backend 404).
class MatterNotFoundException extends MattersException {
  MatterNotFoundException([this.message = 'Nie ma takiej sprawy']);
  @override
  final String message;
}

/// The server refused a write (`title_taken`, `not_proposed`, `link_taken`,
/// `invalid_request`). [message] is the server's own, meant to be shown as it
/// is.
class MatterRefusedException extends MattersException {
  MatterRefusedException(this.code, this.message);

  final String code;
  @override
  final String message;
}

/// What `GET /matters?status=` asks for. [current] sends no status: every
/// matter but the proposed ones.
enum MatterFilter { current, open, closed, proposed, all }

abstract class MattersRepository {
  /// Ordered by the server: proposed, active, waiting, paused, closed, then
  /// newest activity first.
  Future<List<MatterSummary>> fetchMatters({
    MatterFilter filter = MatterFilter.current,
  });

  Future<MatterDetail> fetchMatter(String id);

  Future<MatterDetail> createMatter({
    required String title,
    String keywords = '',
    String nextStep = '',
  });

  /// Changes only the fields given; an empty [nextStep] or [waitingFor]
  /// clears it.
  Future<MatterDetail> editMatter(
    String id, {
    String? title,
    String? keywords,
    MatterStatus? status,
    String? nextStep,
    String? waitingFor,
  });

  Future<void> deleteMatter(String id);

  /// The owner's yes to a proposed matter, as [status] (active or closed).
  Future<MatterDetail> accept(String id, MatterStatus status);

  /// The owner's no to a proposed matter: it is deleted.
  Future<void> drop(String id);

  Future<MatterEntry> addEntry(String id, String text);

  Future<void> deleteEntry(String id, String entryId);

  Future<void> unlink(String id, String linkId);
}
