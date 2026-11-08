import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({super.key, required this.routineId});
  final String routineId;

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  final Set<String> _busyActions = {};

  bool get _isAnyBusy => _busyActions.isNotEmpty;

  void _setBusy(String action) => setState(() => _busyActions.add(action));
  void _clearBusy(String action) => setState(() => _busyActions.remove(action));

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(routineDetailNotifierProvider(widget.routineId));
    final notifier =
        ref.read(routineDetailNotifierProvider(widget.routineId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: _title(state),
      ),
      body: _buildBody(context, state, notifier),
    );
  }

  Widget? _title(RoutineDetailState state) {
    return switch (state) {
      RoutineDetailLoaded(routine: final r) => Text(r.name),
      _ => const Text('Routine'),
    };
  }

  Widget _buildBody(
    BuildContext context,
    RoutineDetailState state,
    RoutineDetailNotifier notifier,
  ) {
    return switch (state) {
      RoutineDetailInitial() =>
        const Center(child: CircularProgressIndicator()),
      RoutineDetailLoading() =>
        const Center(child: CircularProgressIndicator()),
      RoutineDetailLoaded(routine: final routine, occurrences: final occs) =>
        _buildContent(routine, occs, notifier),
      RoutineDetailError(message: final message) =>
        _buildError(message, notifier),
    };
  }

  Widget _buildContent(
    Routine routine,
    List<RoutineOccurrence> occurrences,
    RoutineDetailNotifier notifier,
  ) {
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        children: [
          _StatusSection(
            routine: routine,
            today: formatRoutineDay(ref.read(routinesClockProvider)()),
          ),
          if (routine.steps.isNotEmpty) ...[
            const Divider(),
            _StepsSection(steps: routine.steps),
          ],
          const Divider(),
          if (routine.isRecurring)
            _OccurrencesSection(
              occurrences: occurrences,
              busyActions: _busyActions,
              onUndo: (occ) => _handleUndo(notifier, occ),
            )
          else
            _TickSection(
              routine: routine,
              busyActions: _busyActions,
              isAnyBusy: _isAnyBusy,
              onResolve: (status) => _handleResolve(notifier, status),
              onUndo: (occ) => _handleUndo(notifier, occ),
            ),
          const Divider(),
          _ActionsSection(
            routine: routine,
            busyActions: _busyActions,
            isAnyBusy: _isAnyBusy,
            onActivate: () => _handleActivate(notifier),
            onPause: () => _handlePause(notifier),
            onEdit: () => _handleEdit(routine),
            onEnd: () => _handleEnd(notifier, routine),
            onArchive: () => _handleArchive(notifier, routine),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildError(
    String message,
    RoutineDetailNotifier notifier,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('detail-retry-button'),
            onPressed: notifier.refresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleActivate(RoutineDetailNotifier notifier) async {
    _setBusy('activate');
    final success = await notifier.activateRoutine();
    if (!mounted) return;
    _clearBusy('activate');
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to activate')),
      );
    }
  }

  Future<void> _handlePause(RoutineDetailNotifier notifier) async {
    _setBusy('pause');
    final success = await notifier.pauseRoutine();
    if (!mounted) return;
    _clearBusy('pause');
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(notifier.lastActionError ?? 'Failed to pause')),
      );
    }
  }

  /// Opens the form; an edit changes the routine in place, so the page
  /// reloads it.
  Future<void> _handleEdit(Routine routine) async {
    final saved =
        await context.push<Routine>('/routines/${routine.id}/edit');
    if (!mounted || saved == null) return;
    ref
        .read(routineDetailNotifierProvider(widget.routineId).notifier)
        .refresh();
  }

  /// End after…: the last day the routine still occurs, from yesterday
  /// (ending today) up to its current last day (ending never extends it).
  Future<void> _handleEnd(
      RoutineDetailNotifier notifier, Routine routine) async {
    final now = ref.read(routinesClockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final last = parseRoutineDay(routine.lastDay) ??
        today.add(const Duration(days: 3650));
    final picked = await showDatePicker(
      context: context,
      helpText: 'Last day it occurs',
      confirmText: 'End after',
      initialDate: today.isAfter(last) ? last : today,
      firstDate: yesterday.isAfter(last) ? last : yesterday,
      lastDate: last,
    );
    if (picked == null || !mounted) return;

    _setBusy('end');
    final success = await notifier.endRoutine(formatRoutineDay(picked));
    if (!mounted) return;
    _clearBusy('end');
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.lastActionError ?? 'Failed to end')),
      );
    }
  }

  Future<void> _handleArchive(
      RoutineDetailNotifier notifier, Routine routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Archive “${routine.name}”?'),
        content: const Text(
            'It leaves the agenda and moves to Done and ended.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('archive-confirm-button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _setBusy('archive');
    final success = await notifier.archiveRoutine();
    if (!mounted) return;
    _clearBusy('archive');
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to archive')),
      );
    }
  }


  Future<void> _handleResolve(
    RoutineDetailNotifier notifier,
    OccurrenceStatus status,
  ) async {
    _setBusy('resolve');
    final success = await notifier.resolve(status);
    if (!mounted) return;
    _clearBusy('resolve');
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(notifier.lastActionError ??
                (status == OccurrenceStatus.skipped
                    ? 'Failed to skip'
                    : 'Failed to tick off'))),
      );
    }
  }

  Future<void> _handleUndo(
    RoutineDetailNotifier notifier,
    RoutineOccurrence occurrence,
  ) async {
    final busy = 'undo-${occurrence.id}';
    _setBusy(busy);
    final success = await notifier.undo(occurrence);
    if (!mounted) return;
    _clearBusy(busy);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.lastActionError ?? 'Failed to undo')),
      );
    }
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.routine, required this.today});
  final Routine routine;
  final String today;

  static String _kindLabel(RoutineKind kind) => switch (kind) {
        RoutineKind.recurring => 'recurring',
        RoutineKind.oneOff => 'one-off',
        RoutineKind.someday => 'some day',
      };

  @override
  Widget build(BuildContext context) {
    final status = routineEndBadge(routine) ?? routine.status.name;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Chip(
                key: const Key('detail-status-chip'),
                label: Text(status),
              ),
              Chip(
                key: const Key('detail-kind-chip'),
                label: Text(_kindLabel(routine.kind)),
              ),
              // A one-off always waits; only a recurring routine chooses.
              if (routine.isRecurring)
                Chip(
                  key: const Key('detail-missed-chip'),
                  label: Text(routine.missed.name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(describeRoutine(routine, today: today),
              key: const Key('detail-schedule'),
              style: Theme.of(context).textTheme.bodyMedium),
          if (routine.isRecurring && routine.nextDue != null && !routine.ended)
            Text('Next: ${routine.nextDue}',
                key: const Key('detail-next-due'),
                style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  const _StepsSection({required this.steps});
  final List<RoutineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Steps',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(height: 8),
          ...steps.map((t) => Padding(
                key: Key('step-${t.sortOrder}'),
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text('- ${t.text}',
                    style: Theme.of(context).textTheme.bodyMedium),
              )),
        ],
      ),
    );
  }
}

/// A recurring routine's ticks, newest first; each can be undone.
class _OccurrencesSection extends StatelessWidget {
  const _OccurrencesSection({
    required this.occurrences,
    required this.busyActions,
    required this.onUndo,
  });
  final List<RoutineOccurrence> occurrences;
  final Set<String> busyActions;
  final void Function(RoutineOccurrence occ) onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ticked off',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(height: 8),
          if (occurrences.isEmpty)
            Text('Nothing ticked off yet',
                key: const Key('detail-no-occurrences'),
                style: Theme.of(context).textTheme.bodyMedium),
          ...occurrences.map((occ) => Card(
                key: Key('occurrence-${occ.id}'),
                child: ListTile(
                  leading: _tickIcon(occ.status),
                  title: Text(occ.scheduledFor),
                  subtitle: Text(occ.status.toJson()),
                  trailing: busyActions.contains('undo-${occ.id}')
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          key: Key('occurrence-undo-${occ.id}'),
                          onPressed: () => onUndo(occ),
                          child: const Text('Undo'),
                        ),
                ),
              )),
        ],
      ),
    );
  }
}

/// A one-off or someday routine is ticked off once: Done or Skip while it is
/// open, the tick with Undo once it is resolved.
class _TickSection extends StatelessWidget {
  const _TickSection({
    required this.routine,
    required this.busyActions,
    required this.isAnyBusy,
    required this.onResolve,
    required this.onUndo,
  });
  final Routine routine;
  final Set<String> busyActions;
  final bool isAnyBusy;
  final void Function(OccurrenceStatus status) onResolve;
  final void Function(RoutineOccurrence occ) onUndo;

  @override
  Widget build(BuildContext context) {
    final resolved = routine.resolved;
    if (resolved != null) {
      return ListTile(
        key: const Key('detail-resolved'),
        leading: _tickIcon(resolved.status),
        title: Text(resolved.status == OccurrenceStatus.skipped
            ? 'Skipped'
            : 'Done'),
        subtitle: Text(resolved.scheduledFor),
        trailing: busyActions.contains('undo-${resolved.id}')
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                key: const Key('detail-undo-button'),
                onPressed: isAnyBusy ? null : () => onUndo(resolved),
                child: const Text('Undo'),
              ),
      );
    }
    if (routine.status != RoutineStatus.active) {
      return const ListTile(
        key: Key('detail-not-tickable'),
        title: Text('Resume it to tick it off'),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        children: [
          _ActionButton(
            widgetKey: const Key('detail-done-button'),
            label: 'Done',
            icon: Icons.check,
            isBusy: busyActions.contains('resolve'),
            isDisabled: isAnyBusy,
            onPressed: () => onResolve(OccurrenceStatus.done),
            filled: true,
          ),
          _ActionButton(
            widgetKey: const Key('detail-skip-button'),
            label: 'Skip',
            icon: Icons.skip_next,
            isBusy: false,
            isDisabled: isAnyBusy,
            onPressed: () => onResolve(OccurrenceStatus.skipped),
            filled: false,
          ),
        ],
      ),
    );
  }
}

Widget _tickIcon(OccurrenceStatus status) => switch (status) {
      OccurrenceStatus.done =>
        const Icon(Icons.check_circle, color: Colors.green),
      OccurrenceStatus.skipped =>
        const Icon(Icons.skip_next, color: Colors.orange),
      OccurrenceStatus.pending =>
        const Icon(Icons.schedule, color: Colors.grey),
    };

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({
    required this.routine,
    required this.busyActions,
    required this.isAnyBusy,
    required this.onActivate,
    required this.onPause,
    required this.onEdit,
    required this.onEnd,
    required this.onArchive,
  });
  final Routine routine;
  final Set<String> busyActions;
  final bool isAnyBusy;
  final VoidCallback onActivate;
  final VoidCallback onPause;
  final VoidCallback onEdit;
  final VoidCallback onEnd;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // An edit changes the routine in place; an archived one is final.
          if (routine.status != RoutineStatus.archived)
            _ActionButton(
              widgetKey: const Key('detail-edit-button'),
              label: 'Edit',
              icon: Icons.edit,
              isBusy: false,
              isDisabled: isAnyBusy,
              onPressed: onEdit,
              filled: false,
            ),
          if (!routine.ended && routine.status == RoutineStatus.paused)
            _ActionButton(
              widgetKey: const Key('detail-activate-button'),
              label: 'Activate',
              icon: Icons.play_arrow,
              isBusy: busyActions.contains('activate'),
              isDisabled: isAnyBusy,
              onPressed: onActivate,
              filled: true,
            ),
          if (routine.status == RoutineStatus.active && !routine.ended)
            _ActionButton(
              widgetKey: const Key('detail-pause-button'),
              label: 'Pause',
              icon: Icons.pause,
              isBusy: busyActions.contains('pause'),
              isDisabled: isAnyBusy,
              onPressed: onPause,
              filled: false,
            ),
          if (routine.isRecurring &&
              !routine.ended &&
              routine.status != RoutineStatus.archived)
            _ActionButton(
              widgetKey: const Key('detail-end-button'),
              label: 'End after…',
              icon: Icons.event_busy,
              isBusy: busyActions.contains('end'),
              isDisabled: isAnyBusy,
              onPressed: onEnd,
              filled: false,
            ),
          if (routine.status != RoutineStatus.archived)
            _ActionButton(
              widgetKey: const Key('detail-archive-button'),
              label: 'Archive',
              icon: Icons.archive,
              isBusy: busyActions.contains('archive'),
              isDisabled: isAnyBusy,
              onPressed: onArchive,
              filled: false,
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.widgetKey,
    required this.label,
    required this.icon,
    required this.isBusy,
    required this.isDisabled,
    required this.onPressed,
    required this.filled,
  });

  final Key widgetKey;
  final String label;
  final IconData icon;
  final bool isBusy;
  final bool isDisabled;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = isBusy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 4),
              Text(label),
            ],
          );

    if (filled) {
      return FilledButton(
        key: widgetKey,
        onPressed: isDisabled ? null : onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      key: widgetKey,
      onPressed: isDisabled ? null : onPressed,
      child: child,
    );
  }
}
