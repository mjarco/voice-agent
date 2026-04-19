import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/plan.dart';
import 'package:voice_agent/features/plan/domain/plan_state.dart';
import 'package:voice_agent/features/plan/presentation/plan_notifier.dart';
import 'package:voice_agent/features/plan/presentation/plan_providers.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  final Set<String> _collapsed = {};
  final Set<String> _busyIds = {};

  bool _isBusy(String id) => _busyIds.contains(id);

  void _setBusy(String id) => setState(() => _busyIds.add(id));
  void _clearBusy(String id) => setState(() => _busyIds.remove(id));

  bool _isCollapsed(String section) => _collapsed.contains(section);

  void _toggleSection(String section) =>
      setState(() => _collapsed.contains(section)
          ? _collapsed.remove(section)
          : _collapsed.add(section));

  @override
  void initState() {
    super.initState();
    _collapsed.add('plan-completed-section');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(planNotifierProvider);
    final notifier = ref.read(planNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: switch (state) {
        PlanInitial() => const Center(child: CircularProgressIndicator()),
        PlanLoading() => const Center(child: CircularProgressIndicator()),
        PlanLoaded(plan: final plan) => _buildContent(plan, notifier),
        PlanError(message: final message) => _buildError(message, notifier),
      },
    );
  }

  Widget _buildContent(PlanResponse plan, PlanNotifier notifier) {
    final activeEntries = [
      ...plan.topics.expand((g) => g.items),
      ...plan.uncategorized,
    ];
    final rulesEntries = [
      ...plan.rules.expand((g) => g.items),
      ...plan.rulesUncategorized,
    ];
    final completedEntries = [
      ...plan.completed.expand((g) => g.items),
      ...plan.completedUncategorized,
    ];

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        children: [
          _SectionHeader(
            key: const Key('plan-active-section'),
            title: 'Active Items',
            count: activeEntries.length,
            isCollapsed: _isCollapsed('plan-active-section'),
            onTap: () => _toggleSection('plan-active-section'),
          ),
          if (!_isCollapsed('plan-active-section')) ...[
            ...plan.topics.map(
              (g) => _TopicGroup(
                group: g,
                buildEntry: (entry) => _buildActiveEntry(entry, notifier),
              ),
            ),
            if (plan.uncategorized.isNotEmpty)
              _UncategorizedGroup(
                entries: plan.uncategorized,
                buildEntry: (entry) => _buildActiveEntry(entry, notifier),
              ),
            if (activeEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No items',
                  key: Key('plan-empty-active'),
                ),
              ),
          ],
          const Divider(),
          _SectionHeader(
            key: const Key('plan-rules-section'),
            title: 'Rules',
            count: rulesEntries.length,
            isCollapsed: _isCollapsed('plan-rules-section'),
            onTap: () => _toggleSection('plan-rules-section'),
          ),
          if (!_isCollapsed('plan-rules-section')) ...[
            ...plan.rules.map(
              (g) => _TopicGroup(
                group: g,
                buildEntry: (entry) => _buildRuleEntry(entry, notifier),
              ),
            ),
            if (plan.rulesUncategorized.isNotEmpty)
              _UncategorizedGroup(
                entries: plan.rulesUncategorized,
                buildEntry: (entry) => _buildRuleEntry(entry, notifier),
              ),
            if (rulesEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No items',
                  key: Key('plan-empty-rules'),
                ),
              ),
          ],
          const Divider(),
          _SectionHeader(
            key: const Key('plan-completed-section'),
            title: 'Completed',
            count: completedEntries.length,
            isCollapsed: _isCollapsed('plan-completed-section'),
            onTap: () => _toggleSection('plan-completed-section'),
          ),
          if (!_isCollapsed('plan-completed-section')) ...[
            ...plan.completed.map(
              (g) => _TopicGroup(
                group: g,
                buildEntry: _buildCompletedEntry,
              ),
            ),
            if (plan.completedUncategorized.isNotEmpty)
              _UncategorizedGroup(
                entries: plan.completedUncategorized,
                buildEntry: _buildCompletedEntry,
              ),
            if (completedEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No items',
                  key: Key('plan-empty-completed'),
                ),
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildActiveEntry(PlanEntry entry, PlanNotifier notifier) {
    return _EntryCard(
      entry: entry,
      badge: entry.planBucket?.name,
      isBusy: _isBusy(entry.entryId),
      actions: _activeActions(entry, notifier),
    );
  }

  Widget _buildRuleEntry(PlanEntry entry, PlanNotifier notifier) {
    return _EntryCard(
      entry: entry,
      badge: entry.recordType?.name,
      isBusy: _isBusy(entry.entryId),
      actions: _ruleActions(entry, notifier),
    );
  }

  Widget _buildCompletedEntry(PlanEntry entry) {
    return _EntryCard(
      entry: entry,
      badge: null,
      isBusy: false,
      actions: [],
    );
  }

  List<Widget> _activeActions(PlanEntry entry, PlanNotifier notifier) {
    final id = entry.entryId;
    final busy = _isBusy(id);
    return [
      if (entry.planBucket == PlanBucket.candidate)
        _ActionButton(
          widgetKey: Key('plan-confirm-$id'),
          label: 'Confirm',
          isDisabled: busy,
          onPressed: () => _runAction(id, () => notifier.confirm(id)),
        ),
      _ActionButton(
        widgetKey: Key('plan-done-$id'),
        label: 'Done',
        isDisabled: busy,
        onPressed: () => _runAction(id, () => notifier.markDone(id)),
      ),
      _ActionButton(
        widgetKey: Key('plan-dismiss-$id'),
        label: 'Dismiss',
        isDisabled: busy,
        onPressed: () => _runAction(id, () => notifier.dismiss(id)),
      ),
    ];
  }

  List<Widget> _ruleActions(PlanEntry entry, PlanNotifier notifier) {
    final id = entry.entryId;
    final busy = _isBusy(id);
    return [
      if (entry.recordType == RecordType.decision)
        _ActionButton(
          widgetKey: Key('plan-dismiss-$id'),
          label: 'Dismiss',
          isDisabled: busy,
          onPressed: () => _runAction(id, () => notifier.dismiss(id)),
        ),
      _ActionButton(
        widgetKey: Key('plan-endorse-$id'),
        label: 'Endorse',
        isDisabled: busy,
        onPressed: () => _runAction(id, () => notifier.toggleEndorse(id)),
      ),
    ];
  }

  Future<void> _runAction(String id, Future<bool> Function() action) async {
    _setBusy(id);
    final success = await action();
    if (!mounted) return;
    _clearBusy(id);
    if (!success) {
      final notifier = ref.read(planNotifierProvider.notifier);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notifier.lastActionError ?? 'Action failed'),
        ),
      );
    }
  }

  Widget _buildError(String message, PlanNotifier notifier) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('plan-retry-button'),
            onPressed: notifier.refresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.isCollapsed,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$title ($count)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _TopicGroup extends StatelessWidget {
  const _TopicGroup({required this.group, required this.buildEntry});

  final PlanTopicGroup group;
  final Widget Function(PlanEntry) buildEntry;

  @override
  Widget build(BuildContext context) {
    if (group.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            group.canonicalName,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...group.items.map(buildEntry),
      ],
    );
  }
}

class _UncategorizedGroup extends StatelessWidget {
  const _UncategorizedGroup({
    required this.entries,
    required this.buildEntry,
  });

  final List<PlanEntry> entries;
  final Widget Function(PlanEntry) buildEntry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Uncategorized',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...entries.map(buildEntry),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.badge,
    required this.isBusy,
    required this.actions,
  });

  final PlanEntry entry;
  final String? badge;
  final bool isBusy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('plan-entry-${entry.entryId}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (badge != null) ...[
                  Chip(
                    label: Text(badge!),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    entry.displayText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (isBusy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Wrap(spacing: 4, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.widgetKey,
    required this.label,
    required this.isDisabled,
    required this.onPressed,
  });

  final Key widgetKey;
  final String label;
  final bool isDisabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: widgetKey,
      onPressed: isDisabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }
}
