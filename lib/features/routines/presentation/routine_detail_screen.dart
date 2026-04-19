import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

class RoutineDetailScreen extends ConsumerWidget {
  const RoutineDetailScreen({super.key, required this.routineId});
  final String routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(routineDetailNotifierProvider(routineId));
    final notifier =
        ref.read(routineDetailNotifierProvider(routineId).notifier);

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
        _buildContent(context, routine, occs, notifier),
      RoutineDetailError(message: final message) =>
        _buildError(context, message, notifier),
    };
  }

  Widget _buildContent(
    BuildContext context,
    Routine routine,
    List<RoutineOccurrence> occurrences,
    RoutineDetailNotifier notifier,
  ) {
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        children: [
          _StatusSection(routine: routine),
          if (routine.templates.isNotEmpty) ...[
            const Divider(),
            _TemplatesSection(templates: routine.templates),
          ],
          const Divider(),
          _OccurrencesSection(
            occurrences: occurrences,
            onUpdateStatus: (occId, status) =>
                _handleUpdateOccurrence(context, notifier, occId, status),
          ),
          const Divider(),
          _ActionsSection(
            routine: routine,
            onActivate: () => _handleActivate(context, notifier),
            onPause: () => _handlePause(context, notifier),
            onArchive: () => _handleArchive(context, notifier),
            onTrigger: () => _handleTrigger(context, notifier),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildError(
    BuildContext context,
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

  Future<void> _handleActivate(
    BuildContext context,
    RoutineDetailNotifier notifier,
  ) async {
    final success = await notifier.activateRoutine();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to activate')),
      );
    }
  }

  Future<void> _handlePause(
    BuildContext context,
    RoutineDetailNotifier notifier,
  ) async {
    final success = await notifier.pauseRoutine();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(notifier.lastActionError ?? 'Failed to pause')),
      );
    }
  }

  Future<void> _handleArchive(
    BuildContext context,
    RoutineDetailNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive routine?'),
        content: const Text(
            'This routine will be moved to the archive.'),
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

    final success = await notifier.archiveRoutine();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to archive')),
      );
    }
  }

  Future<void> _handleTrigger(
    BuildContext context,
    RoutineDetailNotifier notifier,
  ) async {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final success = await notifier.triggerRoutine(date);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to trigger')),
      );
    }
  }

  Future<void> _handleUpdateOccurrence(
    BuildContext context,
    RoutineDetailNotifier notifier,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {
    final success =
        await notifier.updateOccurrenceStatus(occurrenceId, status);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                notifier.lastActionError ?? 'Failed to update status')),
      );
    }
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.routine});
  final Routine routine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(
                key: const Key('detail-status-chip'),
                label: Text(routine.status.name),
              ),
              const SizedBox(width: 8),
              if (routine.cadence != null)
                Chip(label: Text(routine.cadence!)),
            ],
          ),
          const SizedBox(height: 8),
          if (routine.startTime != null)
            Text('Start time: ${routine.startTime}',
                style: Theme.of(context).textTheme.bodyMedium),
          if (routine.nextOccurrence != null)
            Text('Next: ${routine.nextOccurrence!.date}',
                key: const Key('detail-next-occurrence'),
                style: Theme.of(context).textTheme.bodyMedium),
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
          Text('Templates',
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
    required this.onActivate,
    required this.onPause,
    required this.onArchive,
    required this.onTrigger,
  });
  final Routine routine;
  final VoidCallback onActivate;
  final VoidCallback onPause;
  final VoidCallback onArchive;
  final VoidCallback onTrigger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (routine.status == RoutineStatus.draft ||
              routine.status == RoutineStatus.paused)
            FilledButton.icon(
              key: const Key('detail-activate-button'),
              onPressed: onActivate,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Activate'),
            ),
          if (routine.status == RoutineStatus.active)
            OutlinedButton.icon(
              key: const Key('detail-pause-button'),
              onPressed: onPause,
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
            ),
          if (routine.status == RoutineStatus.active)
            FilledButton.icon(
              key: const Key('detail-trigger-button'),
              onPressed: onTrigger,
              icon: const Icon(Icons.bolt),
              label: const Text('Trigger Now'),
            ),
          if (routine.status != RoutineStatus.archived)
            OutlinedButton.icon(
              key: const Key('detail-archive-button'),
              onPressed: onArchive,
              icon: const Icon(Icons.archive),
              label: const Text('Archive'),
            ),
        ],
      ),
    );
  }
}
