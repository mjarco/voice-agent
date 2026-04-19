import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';

class CachedAgenda {
  const CachedAgenda({required this.response, required this.fetchedAt});
  final AgendaResponse response;
  final DateTime fetchedAt;
}

abstract class AgendaRepository {
  Future<AgendaResponse> fetchAgenda(String date);
  Future<CachedAgenda?> getCachedAgenda(String date);
  Future<void> cacheAgenda(String date, AgendaResponse response);
  Future<void> markActionItemDone(String recordId);
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  );
}
