import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_notifier.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agendaNotifierProvider);
    final notifier = ref.read(agendaNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            key: const Key('agenda-settings-icon'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          _DateNavigationBar(
            date: notifier.selectedDate,
            isToday: notifier.isToday,
            onPrevious: notifier.previousDay,
            onNext: notifier.nextDay,
            onToday: notifier.goToToday,
          ),
          Expanded(
            child: _buildBody(state, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AgendaState state, AgendaNotifier notifier) {
    return switch (state) {
      AgendaInitial() => const Center(child: CircularProgressIndicator()),
      AgendaLoading(cached: final cached) =>
        cached != null
            ? _buildContent(cached.response, notifier,
                staleAt: cached.fetchedAt, isRefreshing: true)
            : const Center(child: CircularProgressIndicator()),
      AgendaLoaded(response: final response, fetchedAt: final fetchedAt) =>
        _buildContent(response, notifier, staleAt: fetchedAt),
      AgendaError(message: final message, cached: final cached) =>
        cached != null
            ? _buildContent(cached.response, notifier,
                staleAt: cached.fetchedAt, errorMessage: message)
            : _buildError(message, notifier),
    };
  }

  Widget _buildContent(
    AgendaResponse response,
    AgendaNotifier notifier, {
    DateTime? staleAt,
    bool isRefreshing = false,
    String? errorMessage,
  }) {
    final actionItems = response.items;
    final routineItems = response.routineItems;
    final isEmpty = actionItems.isEmpty && routineItems.isEmpty;

    return Column(
      children: [
        if (errorMessage != null)
          MaterialBanner(
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: notifier.refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        if (isRefreshing) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: notifier.refresh,
            child: isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No items for this date',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      if (actionItems.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Action Items',
                          count: actionItems.length,
                        ),
                        ..._sortedActionItems(actionItems).map(
                          (item) => _ActionItemTile(
                            item: item,
                            onMarkDone: () => _handleMarkDone(item.recordId),
                          ),
                        ),
                      ],
                      if (routineItems.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Routines',
                          count: routineItems.length,
                        ),
                        ...routineItems.map(
                          (item) => _RoutineItemTile(
                            item: item,
                            onSkip: item.occurrenceId != null
                                ? () => _handleSkip(
                                    item.routineId, item.occurrenceId!)
                                : null,
                            onComplete: item.occurrenceId != null
                                ? () => _handleComplete(
                                    item.routineId, item.occurrenceId!)
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        if (staleAt != null && !_isRecent(staleAt))
          _StaleDataBanner(fetchedAt: staleAt),
      ],
    );
  }

  List<AgendaItem> _sortedActionItems(List<AgendaItem> items) {
    final sorted = List<AgendaItem>.from(items);
    sorted.sort((a, b) {
      if (a.status == RecordStatus.done && b.status != RecordStatus.done) {
        return 1;
      }
      if (a.status != RecordStatus.done && b.status == RecordStatus.done) {
        return -1;
      }
      return 0;
    });
    return sorted;
  }

  bool _isRecent(DateTime fetchedAt) =>
      DateTime.now().difference(fetchedAt).inMinutes < 5;

  Widget _buildError(String message, AgendaNotifier notifier) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: notifier.refresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMarkDone(String recordId) async {
    final notifier = ref.read(agendaNotifierProvider.notifier);
    final success = await notifier.markDone(recordId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to mark item as done')),
      );
    }
  }

  Future<void> _handleSkip(String routineId, String occurrenceId) async {
    final notifier = ref.read(agendaNotifierProvider.notifier);
    final success = await notifier.skipOccurrence(routineId, occurrenceId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to skip occurrence')),
      );
    }
  }

  Future<void> _handleComplete(String routineId, String occurrenceId) async {
    final notifier = ref.read(agendaNotifierProvider.notifier);
    final success =
        await notifier.completeOccurrence(routineId, occurrenceId);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to complete occurrence')),
      );
    }
  }
}

class _DateNavigationBar extends StatelessWidget {
  const _DateNavigationBar({
    required this.date,
    required this.isToday,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime date;
  final bool isToday;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final formatted = _formatDate(date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('agenda-prev-day'),
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              formatted,
              key: const Key('agenda-date-label'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: const Key('agenda-next-day'),
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
          if (!isToday)
            ActionChip(
              key: const Key('agenda-today-btn'),
              label: const Text('Today'),
              onPressed: onToday,
            ),
        ],
      ),
    );
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
          Text(
            '($count)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ActionItemTile extends StatelessWidget {
  const _ActionItemTile({required this.item, required this.onMarkDone});
  final AgendaItem item;
  final VoidCallback onMarkDone;

  @override
  Widget build(BuildContext context) {
    final isDone = item.status == RecordStatus.done;
    return ListTile(
      key: Key('action-item-${item.recordId}'),
      leading: Checkbox(
        value: isDone,
        onChanged: isDone ? null : (_) => onMarkDone(),
      ),
      title: Text(
        item.text,
        style: isDone
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: item.topicRef != null ? Text(item.topicRef!) : null,
      trailing: _StatusBadge(label: item.status.name),
    );
  }
}

class _RoutineItemTile extends StatelessWidget {
  const _RoutineItemTile({
    required this.item,
    this.onSkip,
    this.onComplete,
  });
  final AgendaRoutineItem item;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('routine-dismiss-${item.routineId}'),
      direction: onSkip != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        color: Colors.orange,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Text('Skip', style: TextStyle(color: Colors.white)),
      ),
      confirmDismiss: (_) async {
        onSkip?.call();
        return false;
      },
      child: ExpansionTile(
        key: Key('routine-item-${item.routineId}'),
        leading: _occurrenceStatusIcon(item.status),
        title: Text(item.routineName),
        subtitle: Row(
          children: [
            if (item.startTime != null) ...[
              Text(item.startTime!),
              const SizedBox(width: 8),
            ],
            _StatusBadge(label: item.status.toJson()),
            if (item.overdue) ...[
              const SizedBox(width: 8),
              const Icon(Icons.warning, size: 16, color: Colors.orange),
            ],
          ],
        ),
        children: [
          ...item.templates.map(
            (t) => ListTile(
              dense: true,
              leading: const Icon(Icons.subdirectory_arrow_right, size: 16),
              title: Text(t.text),
            ),
          ),
          if (onComplete != null &&
              item.status != OccurrenceStatus.done &&
              item.status != OccurrenceStatus.skipped)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton.icon(
                key: Key('routine-complete-${item.routineId}'),
                onPressed: onComplete,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _occurrenceStatusIcon(OccurrenceStatus status) {
    return switch (status) {
      OccurrenceStatus.done =>
        const Icon(Icons.check_circle, color: Colors.green),
      OccurrenceStatus.skipped =>
        const Icon(Icons.skip_next, color: Colors.orange),
      OccurrenceStatus.inProgress =>
        const Icon(Icons.play_circle, color: Colors.blue),
      OccurrenceStatus.pending =>
        const Icon(Icons.schedule, color: Colors.grey),
    };
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _StaleDataBanner extends StatelessWidget {
  const _StaleDataBanner({required this.fetchedAt});
  final DateTime fetchedAt;

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${fetchedAt.hour.toString().padLeft(2, '0')}:${fetchedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      key: const Key('stale-data-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        'Last updated at $formatted',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}
