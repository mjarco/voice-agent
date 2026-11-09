import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/providers/routine_changes_provider.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
import 'package:voice_agent/features/routines/presentation/routines_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

/// Every routine, to manage, folded into the Agenda (the owner's decision of
/// 2026-11-09, ADR-ARCH-012): the Agenda shows what is due, and this section
/// what exists. The router puts it at the end of the Agenda, so neither
/// feature imports the other. Opening it reads the routines again; it stays
/// open across days, and the Agenda and the section tell each other of a change
/// (`routine_changes_provider.dart`).
class RoutinesSection extends ConsumerStatefulWidget {
  const RoutinesSection({super.key});

  @override
  ConsumerState<RoutinesSection> createState() => _RoutinesSectionState();
}

class _RoutinesSectionState extends ConsumerState<RoutinesSection> {
  final Set<String> _busyIds = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(routinesNotifierProvider);
    final notifier = ref.read(routinesNotifierProvider.notifier);
    ref.listen<int>(agendaTickedProvider, (_, _) => notifier.refresh());
    final live = switch (state) {
      RoutinesLoaded(sections: final s) =>
        s.recurring.length + s.tasks.length + s.someday.length + s.paused.length,
      _ => null,
    };

    return ExpansionTile(
      key: const Key('agenda-routines-section'),
      leading: const Icon(Icons.repeat),
      title: Text(live == null ? 'Routines' : 'Routines ($live)'),
      initiallyExpanded: ref.read(routinesSectionOpenProvider),
      onExpansionChanged: (open) {
        ref.read(routinesSectionOpenProvider.notifier).state = open;
        if (open) notifier.refresh();
      },
      children: [
        ListTile(
          key: const Key('routines-new-button'),
          leading: const Icon(Icons.add),
          title: const Text('New routine'),
          onTap: _openNew,
        ),
        ..._buildBody(state, notifier),
      ],
    );
  }

  List<Widget> _buildBody(RoutinesState state, RoutinesNotifier notifier) {
    return switch (state) {
      RoutinesInitial() || RoutinesLoading() => const [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      RoutinesLoaded(sections: final sections) => _buildContent(sections),
      RoutinesError(message: final message) => [
          _buildError(message, notifier),
        ],
    };
  }

  List<Widget> _buildContent(RoutineSections sections) {
    final today = formatRoutineDay(ref.read(routinesClockProvider)());
    Widget card(Routine r) => _RoutineCard(
          routine: r,
          today: today,
          isBusy: _busyIds.contains(r.id),
          onTap: () => _navigateToDetail(r.id),
          onPause: r.status == RoutineStatus.active && !r.ended
              ? () => _handlePause(r.id)
              : null,
          onResume: r.status == RoutineStatus.paused && !r.ended
              ? () => _handleResume(r.id)
              : null,
        );
    List<Widget> section(String key, String title, List<Routine> routines) => [
          if (routines.isNotEmpty) ...[
            _SectionHeader(
                key: Key('routines-section-$key'),
                title: title,
                count: routines.length),
            ...routines.map(card),
          ],
        ];
    if (sections.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No routines or tasks yet',
            key: Key('routines-empty-state'),
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ];
    }
    return [
      ...section('recurring', 'Routines', sections.recurring),
      ...section('tasks', 'Tasks', sections.tasks),
      ...section('someday', 'Some day', sections.someday),
      ...section('paused', 'Paused', sections.paused),
      if (sections.finished.isNotEmpty)
        // Collapsed: it only grows.
        ExpansionTile(
          key: const Key('routines-section-finished'),
          title: Text('Done and ended (${sections.finished.length})'),
          children: sections.finished.map(card).toList(),
        ),
    ];
  }

  Widget _buildError(String message, RoutinesNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('routines-retry-button'),
            onPressed: notifier.refresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNew() async {
    final created = await context.push<Routine>('/agenda/routines/new');
    if (!mounted || created == null) return;
    ref.read(routinesNotifierProvider.notifier).refresh();
    ref.read(routinesEditedProvider.notifier).state++;
  }

  Future<void> _navigateToDetail(String routineId) async {
    await context.push('/agenda/routines/$routineId');
    if (mounted) {
      ref.read(routinesNotifierProvider.notifier).refresh();
      ref.read(routinesEditedProvider.notifier).state++;
    }
  }

  Future<void> _handlePause(String id) async {
    setState(() => _busyIds.add(id));
    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.pauseRoutine(id);
    if (mounted) setState(() => _busyIds.remove(id));
    if (success && mounted) ref.read(routinesEditedProvider.notifier).state++;
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to pause')),
      );
    }
  }

  Future<void> _handleResume(String id) async {
    setState(() => _busyIds.add(id));
    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.activateRoutine(id);
    if (mounted) setState(() => _busyIds.remove(id));
    if (success && mounted) ref.read(routinesEditedProvider.notifier).state++;
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to resume')),
      );
    }
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.today,
    required this.isBusy,
    required this.onTap,
    this.onPause,
    this.onResume,
  });
  final Routine routine;
  final String today;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final badge = routineEndBadge(routine);
    return Card(
      key: Key('routine-card-${routine.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(routine.name,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            badge.toUpperCase(),
                            key: Key('routine-badge-${routine.id}'),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.secondary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      describeRoutine(routine, today: today),
                      key: Key('routine-schedule-${routine.id}'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (routine.isRecurring &&
                        routine.nextDue != null &&
                        !routine.ended)
                      Text(
                        'Next: ${routine.nextDue}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                if (onPause != null)
                  IconButton(
                    key: Key('routine-pause-${routine.id}'),
                    icon: const Icon(Icons.pause),
                    tooltip: 'Pause',
                    onPressed: onPause,
                  ),
                if (onResume != null)
                  IconButton(
                    key: Key('routine-resume-${routine.id}'),
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'Resume',
                    onPressed: onResume,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(width: 8),
          Text('($count)', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
