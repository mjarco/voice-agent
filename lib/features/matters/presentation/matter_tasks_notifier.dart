import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';

/// One task of a matter's agenda as the screen shows it (04 §4 of the
/// discussion): when it is due in words, whether it is overdue, and the day a
/// tick is for.
class MatterTask {
  const MatterTask({
    required this.routine,
    required this.when,
    required this.overdue,
    required this.canTick,
    this.scheduledFor,
  });

  final Routine routine;

  /// "pon 17.11", "od 10.11", "kiedyś", "co pon · 17.11".
  final String when;
  final bool overdue;

  /// A swipe can tick it off: a one-off or someday task, or a recurring one
  /// due today or before.
  final bool canTick;

  /// The day a recurring routine's tick is for; null for the others.
  final String? scheduledFor;

  String get id => routine.id;

  static const _weekdays = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'niedz'];

  static String _short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  static MatterTask of(Routine r, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    final next = r.nextDue == null ? null : DateTime.tryParse(r.nextDue!);
    if (r.isRecurring) {
      final due = next != null && !next.isAfter(day);
      return MatterTask(
        routine: r,
        when: next == null ? 'cyklicznie' : 'cyklicznie · ${_weekdays[next.weekday - 1]} ${_short(next)}',
        overdue: next != null && next.isBefore(day),
        canTick: due,
        scheduledFor: due ? r.nextDue : null,
      );
    }
    if (next == null) {
      return MatterTask(routine: r, when: 'kiedyś', overdue: false, canTick: true);
    }
    if (next.isBefore(day)) {
      return MatterTask(routine: r, when: 'od ${_short(next)}', overdue: true, canTick: true);
    }
    final when = next == day
        ? 'dziś'
        : next == day.add(const Duration(days: 1))
            ? 'jutro'
            : '${_weekdays[next.weekday - 1]} ${_short(next)}';
    return MatterTask(routine: r, when: when, overdue: false, canTick: true);
  }

  /// Overdue first, then by day, someday last.
  static int compare(MatterTask a, MatterTask b) {
    if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
    final da = a.routine.nextDue, db = b.routine.nextDue;
    if (da == null && db == null) return a.routine.name.compareTo(b.routine.name);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }
}

sealed class MatterTasksState {
  const MatterTasksState();
}

class MatterTasksLoading extends MatterTasksState {
  const MatterTasksLoading();
}

class MatterTasksLoaded extends MatterTasksState {
  const MatterTasksLoaded(this.tasks);
  final List<MatterTask> tasks;
}

class MatterTasksError extends MatterTasksState {
  const MatterTasksError(this.message);
  final String message;
}

/// A matter's agenda: its open tasks, added, ticked off and removed from the
/// matter's screen (the owner's M6: "zobaczyć moją agendę powiązaną z daną
/// sprawą i móc dodać nowe zadanie lub usunąć stare"). Each write returns
/// true on success and reads the agenda again; on failure it records
/// [lastActionError].
class MatterTasksNotifier extends StateNotifier<MatterTasksState> {
  MatterTasksNotifier(this._repository, this._matterId, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const MatterTasksLoading()) {
    load();
  }

  final MattersRepository _repository;
  final String _matterId;
  final DateTime Function() _now;
  String? lastActionError;

  Future<void> load() async {
    try {
      final routines = await _repository.fetchTasks(_matterId);
      final today = _now();
      final tasks = [
        for (final r in routines)
          if (!r.ended && r.status == RoutineStatus.active) MatterTask.of(r, today),
      ]..sort(MatterTask.compare);
      if (mounted) state = MatterTasksLoaded(tasks);
    } catch (e) {
      if (mounted && state is! MatterTasksLoaded) state = MatterTasksError(e.toString());
    }
  }

  /// Takes a task off the screen at once (a swipe), before its write returns.
  void hide(String id) {
    final s = state;
    if (s is MatterTasksLoaded) {
      state = MatterTasksLoaded([for (final t in s.tasks) if (t.id != id) t]);
    }
  }

  Future<bool> add(String name, {String? dueOn}) =>
      _write(() => _repository.addTask(_matterId, name, dueOn: dueOn));

  Future<bool> done(MatterTask t) =>
      _write(() => _repository.resolveTask(t.id, scheduledFor: t.scheduledFor));

  Future<bool> undoDone(MatterTask t) =>
      _write(() => _repository.unresolveTask(t.id, scheduledFor: t.scheduledFor));

  Future<bool> remove(MatterTask t) => _write(() => _repository.archiveTask(t.id));

  Future<bool> restore(MatterTask t) => _write(() => _repository.restoreTask(t.id));

  Future<bool> _write(Future<Object?> Function() call) async {
    lastActionError = null;
    try {
      await call();
      if (mounted) await load();
      return true;
    } catch (e) {
      lastActionError = e is MattersException ? e.message : e.toString();
      if (mounted) await load();
      return false;
    }
  }
}
