import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
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

  static const _tabs = [
    RoutineStatus.active,
    RoutineStatus.draft,
    RoutineStatus.paused,
    RoutineStatus.archived,
  ];

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
        .selectStatus(_tabs[_tabController.index]);
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
            Tab(text: 'Draft'),
            Tab(text: 'Paused'),
            Tab(text: 'Archived'),
          ],
        ),
      ),
      body: _buildBody(state, notifier),
    );
  }

  Widget _buildBody(RoutinesState state, RoutinesNotifier notifier) {
    return switch (state) {
      RoutinesInitial() => const Center(child: CircularProgressIndicator()),
      RoutinesLoading() => const Center(child: CircularProgressIndicator()),
      RoutinesLoaded(routines: final routines, proposals: final proposals) =>
        _buildContent(routines, proposals, notifier),
      RoutinesError(message: final message) =>
        _buildError(message, notifier),
    };
  }

  Widget _buildContent(
    List<Routine> routines,
    List<RoutineProposal> proposals,
    RoutinesNotifier notifier,
  ) {
    final showProposals =
        proposals.isNotEmpty && _tabController.index == 0;

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: routines.isEmpty && !showProposals
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
              children: [
                if (showProposals) ...[
                  _SectionHeader(
                    title: 'Proposals',
                    count: proposals.length,
                  ),
                  ...proposals.map((p) => _ProposalCard(
                        proposal: p,
                        onApprove: () => _handleApprove(p.id),
                        onReject: () => _handleReject(p.id),
                      )),
                  const Divider(),
                ],
                ...routines.map((r) => _RoutineCard(
                      routine: r,
                      onTap: () => _navigateToDetail(r.id),
                      onTrigger:
                          r.status == RoutineStatus.active
                              ? () => _handleTrigger(r.id)
                              : null,
                      onPause:
                          r.status == RoutineStatus.active
                              ? () => _handlePause(r.id)
                              : null,
                    )),
              ],
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

  Future<void> _navigateToDetail(String routineId) async {
    await context.push('/routines/$routineId');
    if (mounted) {
      ref.read(routinesNotifierProvider.notifier).refresh();
    }
  }

  Future<void> _handleTrigger(String id) async {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.triggerRoutine(id, date);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to trigger')),
      );
    }
  }

  Future<void> _handlePause(String id) async {
    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.pauseRoutine(id);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to pause')),
      );
    }
  }

  Future<void> _handleApprove(String proposalId) async {
    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.approveProposal(proposalId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to approve')),
      );
    }
  }

  Future<void> _handleReject(String proposalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject proposal?'),
        content:
            const Text('This proposal will be permanently dismissed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('reject-confirm-button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final notifier = ref.read(routinesNotifierProvider.notifier);
    final success = await notifier.rejectProposal(proposalId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(notifier.lastActionError ?? 'Failed to reject')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
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

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onApprove,
    required this.onReject,
  });
  final RoutineProposal proposal;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('proposal-card-${proposal.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(proposal.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (proposal.cadence != null)
                  Chip(label: Text(proposal.cadence!)),
              ],
            ),
            const SizedBox(height: 8),
            ...proposal.items.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text('- ${item.text}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('proposal-reject-${proposal.id}'),
                  onPressed: onReject,
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('proposal-approve-${proposal.id}'),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.onTap,
    this.onTrigger,
    this.onPause,
  });
  final Routine routine;
  final VoidCallback onTap;
  final VoidCallback? onTrigger;
  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
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
                    Text(routine.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (routine.cadence != null) ...[
                          Text(routine.cadence!,
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: 12),
                        ],
                        if (routine.nextOccurrence != null)
                          Text(
                            'Next: ${routine.nextOccurrence!.date}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTrigger != null)
                IconButton(
                  key: Key('routine-trigger-${routine.id}'),
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Trigger now',
                  onPressed: onTrigger,
                ),
              if (onPause != null)
                IconButton(
                  key: Key('routine-pause-${routine.id}'),
                  icon: const Icon(Icons.pause),
                  tooltip: 'Pause',
                  onPressed: onPause,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
