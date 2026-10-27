import 'dart:async';

import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

Routine sampleRoutine({
  String id = 'rtn-1',
  String name = 'Morning routine',
  String rrule = 'FREQ=DAILY',
  RoutineStatus status = RoutineStatus.active,
  RoutineMissed missed = RoutineMissed.lapses,
  String? startTime,
  String? activeSince,
  String? lastDay,
  bool ended = false,
  String? previousRoutineId,
  String? nextRoutineId,
  List<RoutineTemplate> templates = const [],
}) =>
    Routine(
      id: id,
      sourceRecordId: 'src-1',
      name: name,
      rrule: rrule,
      status: status,
      missed: missed,
      startTime: startTime,
      activeSince: activeSince,
      lastDay: lastDay,
      ended: ended,
      previousRoutineId: previousRoutineId,
      nextRoutineId: nextRoutineId,
      templates: templates,
      createdAt: DateTime(2026, 4, 1),
      updatedAt: DateTime(2026, 4, 18),
    );

/// An in-memory [RoutinesRepository] that records the calls it gets.
class FakeRoutinesRepository implements RoutinesRepository {
  final Map<RoutineStatus, List<Routine>> byStatus = {};
  Routine? detail;
  List<RoutineOccurrence> occurrences = [];
  Exception? fetchError;
  Exception? actionError;

  /// Answers of create/edit, in order: a [Routine] is returned, an
  /// [Exception] thrown.
  final List<Object> saveAnswers = [];

  /// When set, fetchRoutineDetail waits for it.
  Completer<void>? detailGate;

  final List<RoutineStatus> fetchedStatuses = [];
  final List<String> calls = [];
  RoutineInput? lastInput;
  String? lastStartsOn;
  String? lastEndDay;
  ({String routineId, String day, OccurrenceStatus status})? lastResolve;

  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async {
    fetchedStatuses.add(status);
    if (fetchError != null) throw fetchError!;
    return byStatus[status] ?? const [];
  }

  @override
  Future<Routine> fetchRoutineDetail(String id) async {
    calls.add('detail $id');
    if (detailGate != null) await detailGate!.future;
    if (fetchError != null) throw fetchError!;
    return detail ?? sampleRoutine(id: id);
  }

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async {
    if (fetchError != null) throw fetchError!;
    return occurrences;
  }

  Future<Routine> _nextSave() async {
    final answer = saveAnswers.isEmpty ? sampleRoutine(id: 'rtn-new') : saveAnswers.removeAt(0);
    if (answer is Exception) throw answer;
    return answer as Routine;
  }

  @override
  Future<Routine> createRoutine(RoutineInput input) {
    calls.add('create');
    lastInput = input;
    return _nextSave();
  }

  @override
  Future<Routine> editRoutine(String id, RoutineInput input,
      {required String startsOn}) {
    calls.add('edit $id');
    lastInput = input;
    lastStartsOn = startsOn;
    return _nextSave();
  }

  @override
  Future<void> endRoutine(String id, String lastDay) async {
    calls.add('end $id');
    lastEndDay = lastDay;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> resolveOccurrence(
      String routineId, String scheduledFor, OccurrenceStatus status) async {
    calls.add('resolve $routineId $scheduledFor ${status.toJson()}');
    lastResolve = (routineId: routineId, day: scheduledFor, status: status);
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> activateRoutine(String id) async {
    calls.add('activate $id');
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> pauseRoutine(String id) async {
    calls.add('pause $id');
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> archiveRoutine(String id) async {
    calls.add('archive $id');
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> updateOccurrenceStatus(
      String routineId, String occurrenceId, OccurrenceStatus status) async {
    calls.add('occurrence $occurrenceId ${status.toJson()}');
    if (actionError != null) throw actionError!;
  }
}
