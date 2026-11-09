import 'dart:async';

import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

Routine sampleRoutine({
  String id = 'rtn-1',
  String name = 'Morning routine',
  RoutineKind? kind,
  String rrule = 'FREQ=DAILY',
  String? dueOn,
  TimeWindow? dueWindow,
  RoutineStatus status = RoutineStatus.active,
  RoutineMissed missed = RoutineMissed.lapses,
  String? startTime,
  String? activeSince,
  String? lastDay,
  String? nextDue,
  bool ended = false,
  RoutineOccurrence? resolved,
  List<RoutineStep> steps = const [],
  bool existing = false,
  DateTime? updatedAt,
}) {
  final k = kind ??
      (dueOn != null ? RoutineKind.oneOff : RoutineKind.recurring);
  return Routine(
    id: id,
    name: name,
    kind: k,
    rrule: k == RoutineKind.recurring ? rrule : '',
    dueOn: dueOn,
    dueWindow: dueWindow ?? (dueOn != null ? TimeWindow.day : null),
    status: status,
    missed: k == RoutineKind.recurring ? missed : RoutineMissed.waits,
    startTime: startTime,
    activeSince: activeSince,
    lastDay: lastDay,
    nextDue: nextDue,
    ended: ended,
    resolved: resolved,
    steps: steps,
    existing: existing,
    createdAt: DateTime(2026, 4, 1),
    updatedAt: updatedAt ?? DateTime(2026, 4, 18),
  );
}

RoutineOccurrence sampleOccurrence({
  String id = 'occ-1',
  String routineId = 'rtn-1',
  String scheduledFor = '2026-04-19',
  OccurrenceStatus status = OccurrenceStatus.done,
}) =>
    RoutineOccurrence(
      id: id,
      routineId: routineId,
      scheduledFor: scheduledFor,
      status: status,
      createdAt: DateTime(2026, 4, 19, 8),
      updatedAt: DateTime(2026, 4, 19, 8),
    );

/// An in-memory [RoutinesRepository] that records the calls it gets.
class FakeRoutinesRepository implements RoutinesRepository {
  List<Routine> routines = [];
  Routine? detail;

  /// Details by id, ahead of [detail].
  final Map<String, Routine> detailsById = {};
  List<RoutineOccurrence> occurrences = [];
  Exception? fetchError;
  Exception? actionError;

  /// Answers of create/edit, in order: a [Routine] is returned, an
  /// [Exception] thrown.
  final List<Object> saveAnswers = [];

  /// When set, fetchRoutineDetail waits for it.
  Completer<void>? detailGate;

  int fetchCount = 0;
  final List<String> calls = [];
  RoutineInput? lastInput;
  RoutinePatch? lastPatch;
  ({String routineId, String? day, OccurrenceStatus status})? lastResolve;
  ({String routineId, String? day})? lastUnresolve;

  @override
  Future<List<Routine>> fetchRoutines() async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    return routines;
  }

  @override
  Future<Routine> fetchRoutineDetail(String id) async {
    calls.add('detail $id');
    if (detailGate != null) await detailGate!.future;
    if (fetchError != null) throw fetchError!;
    return detailsById[id] ?? detail ?? sampleRoutine(id: id);
  }

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async {
    if (fetchError != null) throw fetchError!;
    return occurrences;
  }

  Future<Routine> _nextSave() async {
    final answer =
        saveAnswers.isEmpty ? sampleRoutine(id: 'rtn-new') : saveAnswers.removeAt(0);
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
  Future<Routine> editRoutine(String id, RoutinePatch patch) {
    calls.add('edit $id');
    lastPatch = patch;
    return _nextSave();
  }

  @override
  Future<void> resolve(String routineId, OccurrenceStatus status,
      {String? scheduledFor}) async {
    calls.add('resolve $routineId $scheduledFor ${status.toJson()}');
    lastResolve = (routineId: routineId, day: scheduledFor, status: status);
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> unresolve(String routineId, {String? scheduledFor}) async {
    calls.add('unresolve $routineId $scheduledFor');
    lastUnresolve = (routineId: routineId, day: scheduledFor);
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
}
