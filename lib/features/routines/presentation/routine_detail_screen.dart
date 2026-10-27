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
            onOpen: (id) => context.push('/routines/$id'),
          ),
          if (routine.templates.isNotEmpty) ...[
            const Divider(),
            _TemplatesSection(templates: routine.templates),
          ],
          const Divider(),
          _OccurrencesSection(
            occurrences: occurrences,
            onUpdateStatus: (occId, status) =>
                _handleUpdateOccurrence(notifier, occId, status),
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

  /// Opens the form; a saved edit shows the new version in place of this one.
  Future<void> _handleEdit(Routine routine) async {
    final saved =
        await context.push<Routine>('/routines/${routine.id}/edit');
    if (!mounted || saved == null) return;
    context.replace('/routines/${saved.id}');
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
            'It leaves the agenda and moves to Ended.'),
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


  Future<void> _handleUpdateOccurrence(
    RoutineDetailNotifier notifier,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {
    final success =
        await notifier.updateOccurrenceStatus(occurrenceId, status);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                notifier.lastActionError ?? 'Failed to update status')),
      );
    }
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.routine,
    required this.today,
    required this.onOpen,
  });
  final Routine routine;
  final String today;
  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    final status = routine.ended && routine.status != RoutineStatus.archived
        ? 'ended'
        : routine.status.name;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(
                key: const Key('detail-status-chip'),
                label: Text(status),
              ),
              const SizedBox(width: 8),
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
          if (routine.nextOccurrence != null && !routine.ended)
            Text('Next: ${routine.nextOccurrence!.date}',
                key: const Key('detail-next-occurrence'),
                style: Theme.of(context).textTheme.bodyMedium),
          if (routine.nextRoutineId != null || routine.previousRoutineId != null)
            Wrap(
              spacing: 8,
              children: [
                if (routine.previousRoutineId != null)
                  TextButton(
                    key: const Key('detail-previous-version'),
                    onPressed: () => onOpen(routine.previousRoutineId!),
                    child: const Text('Previous version'),
                  ),
                if (routine.nextRoutineId != null)
                  TextButton(
                    key: const Key('detail-next-version'),
                    onPressed: () => onOpen(routine.nextRoutineId!),
                    child: const Text('Newer version'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TemplatesSection extends StatelessWidget {
  const _TemplatesSection({required this.templates});
  final List<RoutineTemplate> templates;

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
          ...templates.map((t) => Padding(
                key: Key('template-${t.sortOrder}'),
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text('- ${t.text}',
                    style: Theme.of(context).textTheme.bodyMedium),
              )),
        ],
      ),
    );
  }
}

class _OccurrencesSection extends StatelessWidget {
  const _OccurrencesSection({
    required this.occurrences,
    required this.onUpdateStatus,
  });
  final List<RoutineOccurrence> occurrences;
  final void Function(String occId, OccurrenceStatus status) onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Occurrences',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(height: 8),
          if (occurrences.isEmpty)
            Text('No occurrences yet',
                key: const Key('detail-no-occurrences'),
                style: Theme.of(context).textTheme.bodyMedium),
          ...occurrences.map((occ) => Card(
                key: Key('occurrence-${occ.id}'),
                child: ListTile(
                  title: Text(occ.scheduledFor),
                  subtitle: Text(occ.status.toJson()),
                  trailing: _buildOccurrenceActions(occ),
                ),
              )),
        ],
      ),
    );
  }

  Widget? _buildOccurrenceActions(RoutineOccurrence occ) {
    if (occ.status == OccurrenceStatus.done ||
        occ.status == OccurrenceStatus.skipped) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (occ.status == OccurrenceStatus.pending)
          IconButton(
            key: Key('occurrence-start-${occ.id}'),
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Start',
            onPressed: () =>
                onUpdateStatus(occ.id, OccurrenceStatus.inProgress),
          ),
        IconButton(
          key: Key('occurrence-done-${occ.id}'),
          icon: const Icon(Icons.check),
          tooltip: 'Done',
          onPressed: () => onUpdateStatus(occ.id, OccurrenceStatus.done),
        ),
        IconButton(
          key: Key('occurrence-skip-${occ.id}'),
          icon: const Icon(Icons.skip_next),
          tooltip: 'Skip',
          onPressed: () =>
              onUpdateStatus(occ.id, OccurrenceStatus.skipped),
        ),
      ],
    );
  }
}

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
          // An edit replaces the newest version only.
          if (routine.nextRoutineId == null)
            _ActionButton(
              widgetKey: const Key('detail-edit-button'),
              label: 'Edit',
              icon: Icons.edit,
              isBusy: false,
              isDisabled: isAnyBusy,
              onPressed: onEdit,
              filled: false,
            ),
          if (!routine.ended &&
              (routine.status == RoutineStatus.draft ||
                  routine.status == RoutineStatus.paused))
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
          if (!routine.ended && routine.status != RoutineStatus.archived)
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
