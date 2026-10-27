import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
import 'package:voice_agent/features/routines/presentation/routines_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

class RoutinesScreen extends ConsumerStatefulWidget {
  const RoutinesScreen({super.key});

  @override
  ConsumerState<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends ConsumerState<RoutinesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = RoutinesTab.values;

  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    ref
        .read(routinesNotifierProvider.notifier)
        .selectTab(_tabs[_tabController.index]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(routinesNotifierProvider);
    final notifier = ref.read(routinesNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        actions: [
          IconButton(
            key: const Key('routines-settings-icon'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Paused'),
            Tab(text: 'Ended'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('routines-new-button'),
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('New routine'),
      ),
      body: _buildBody(state, notifier),
    );
  }

  Widget _buildBody(RoutinesState state, RoutinesNotifier notifier) {
    return switch (state) {
      RoutinesInitial() => const Center(child: CircularProgressIndicator()),
      RoutinesLoading() => const Center(child: CircularProgressIndicator()),
      RoutinesLoaded(routines: final routines) =>
        _buildContent(routines, notifier),
      RoutinesError(message: final message) =>
        _buildError(message, notifier),
    };
  }

  Widget _buildContent(List<Routine> routines, RoutinesNotifier notifier) {
    final today = formatRoutineDay(ref.read(routinesClockProvider)());
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: routines.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.event_repeat,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No ${_tabs[_tabController.index].name} routines',
                        key: const Key('routines-empty-state'),
                        style: const TextStyle(
                            fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              // Room for the New routine button over the last card.
              padding: const EdgeInsets.only(bottom: 88),
              children: routines
                  .map((r) => _RoutineCard(
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
                      ))
                  .toList(),
            ),
    );
  }

  Widget _buildError(String message, RoutinesNotifier notifier) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('routines-retry-button'),
            onPressed: notifier.refresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNew() async {
    final created = await context.push<Routine>('/routines/new');
    if (!mounted || created == null) return;
    ref.read(routinesNotifierProvider.notifier).refresh();
  }

  Future<void> _navigateToDetail(String routineId) async {
    await context.push('/routines/$routineId');
    if (mounted) {
      ref.read(routinesNotifierProvider.notifier).refresh();
    }
  }

  Future<void> _handlePause(String id) async {
    setState(() => _busyIds.add(id));
    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.pauseRoutine(id);
    if (mounted) setState(() => _busyIds.remove(id));
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
    final badge = switch (routine) {
      Routine(status: RoutineStatus.archived) => 'archived',
      Routine(status: RoutineStatus.draft) => 'draft',
      _ => null,
    };
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
                    if (routine.nextOccurrence != null && !routine.ended)
                      Text(
                        'Next: ${routine.nextOccurrence!.date}',
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
