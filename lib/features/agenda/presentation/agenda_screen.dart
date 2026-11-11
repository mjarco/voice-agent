import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/providers/routine_changes_provider.dart';
import 'package:voice_agent/core/widgets/app_bar_actions.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_notifier.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key, this.footer});

  /// Shown below the day, on every day: the router puts the routines' section
  /// here (ADR-ARCH-012), so this feature does not import another.
  final Widget? footer;

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agendaNotifierProvider);
    final notifier = ref.read(agendaNotifierProvider.notifier);
    ref.listen<int>(routinesEditedProvider, (_, _) => notifier.refresh());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: const [AppBarActions()],
      ),
      body: Column(
        children: [
          _DateNavigationBar(
            date: notifier.selectedDate,
            isToday: notifier.isToday,
            onPrevious: notifier.canGoBack ? notifier.previousDay : null,
            onNext: notifier.nextDay,
            onToday: notifier.goToToday,
          ),
          Expanded(child: _buildBody(state, notifier)),
        ],
      ),
    );
  }

  /// The footer keeps its place and its state across days and reloads: a key
  /// of its own, so a different count of rows above does not rebuild it.
  Widget? get _footer => widget.footer == null
      ? null
      : KeyedSubtree(
          key: const ValueKey('agenda-footer'),
          child: widget.footer!,
        );

  /// A day still loading or failed with nothing cached shows its state above
  /// the footer: the routines read their own endpoint and may still answer.
  Widget _withFooter(Widget top) {
    final footer = _footer;
    if (footer == null) return top;
    return ListView(
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: top),
        footer,
      ],
    );
  }

  Widget _buildBody(AgendaState state, AgendaNotifier notifier) {
    return switch (state) {
      AgendaInitial() =>
        _withFooter(const Center(child: CircularProgressIndicator())),
      AgendaLoading(cached: final cached) =>
        cached != null
            ? _buildContent(
                cached.response,
                notifier,
                staleAt: cached.fetchedAt,
                isRefreshing: true,
              )
            : _withFooter(const Center(child: CircularProgressIndicator())),
      AgendaLoaded(response: final response, fetchedAt: final fetchedAt) =>
        _buildContent(response, notifier, staleAt: fetchedAt),
      AgendaError(message: final message, cached: final cached) =>
        cached != null
            ? _buildContent(
                cached.response,
                notifier,
                staleAt: cached.fetchedAt,
                errorMessage: message,
              )
            : _withFooter(_buildError(message, notifier)),
    };
  }

  Widget _buildContent(
    AgendaResponse response,
    AgendaNotifier notifier, {
    DateTime? staleAt,
    bool isRefreshing = false,
    String? errorMessage,
  }) {
    final routineItems = response.routineItems;
    final meetings = response.calendarItems;
    final ticked = response.tickedItems;
    final isEmpty = routineItems.isEmpty && meetings.isEmpty && ticked.isEmpty;

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
            onRefresh: () async {
              ref.read(agendaTickedProvider.notifier).state++;
              await notifier.refreshWithCalendars();
            },
            child: isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No items for this date',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ?_footer,
                    ],
                  )
                : ListView(
                    children: [
                      if (meetings.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Meetings',
                          count: meetings.length,
                        ),
                        ...meetings.map(
                          (m) => _MeetingTile(meeting: m, day: response.date),
                        ),
                      ],
                      if (routineItems.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'To do',
                          count: routineItems.length,
                        ),
                        // The server's order: overdue first, then by day,
                        // hour and name.
                        ...routineItems.map(
                          (item) => _RoutineItemTile(
                            item: item,
                            onSkip: () =>
                                _handleResolve(item, OccurrenceStatus.skipped),
                            onComplete: () =>
                                _handleResolve(item, OccurrenceStatus.done),
                          ),
                        ),
                      ],
                      if (ticked.isNotEmpty)
                        // Folded: what was ticked on the day, newest first,
                        // each with its Undo.
                        ExpansionTile(
                          key: const Key('agenda-ticked-section'),
                          title: Text(
                            '${notifier.isToday ? 'Done today' : 'Done that day'} (${ticked.length})',
                          ),
                          children: ticked
                              .map(
                                (t) => _TickedTile(
                                  item: t,
                                  day: response.date,
                                  onUndo: () => _handleUndoTicked(t),
                                ),
                              )
                              .toList(),
                        ),
                      ?_footer,
                    ],
                  ),
          ),
        ),
        if (staleAt != null && !_isRecent(staleAt))
          _StaleDataBanner(fetchedAt: staleAt),
      ],
    );
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

  /// Ticks the row off; a ticked row leaves the agenda, so the snackbar
  /// offers to undo it.
  Future<void> _handleResolve(
    AgendaRoutineItem item,
    OccurrenceStatus status,
  ) async {
    final notifier = ref.read(agendaNotifierProvider.notifier);
    final refusal = await notifier.resolveOccurrence(item, status);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (refusal != null) {
      messenger.showSnackBar(SnackBar(content: Text(refusal)));
      return;
    }
    ref.read(agendaTickedProvider.notifier).state++;
    final verb = status == OccurrenceStatus.skipped ? 'Skipped' : 'Done';
    // The newest tick's Undo shows at once, not behind an older one.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: Key('agenda-ticked-${item.routineId}'),
        content: Text('$verb: ${item.routineName}'),
        // A snackbar with an action stays until dismissed unless told
        // otherwise; the Undo must run out by itself.
        persist: false,
        action: SnackBarAction(
          key: Key('agenda-undo-${item.routineId}'),
          label: 'Undo',
          onPressed: () => _handleUndo(item),
        ),
      ),
    );
  }

  Future<void> _handleUndoTicked(AgendaTickedItem item) async {
    final notifier = ref.read(agendaNotifierProvider.notifier);
    final refusal = await notifier.undoTicked(item);
    if (refusal == null && mounted) {
      ref.read(agendaTickedProvider.notifier).state++;
    }
    if (refusal != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(refusal)));
    }
  }

  Future<void> _handleUndo(AgendaRoutineItem item) async {
    final notifier = ref.read(agendaNotifierProvider.notifier);
    final refusal = await notifier.undoOccurrence(item);
    if (refusal == null && mounted) {
      ref.read(agendaTickedProvider.notifier).state++;
    }
    if (refusal != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(refusal)));
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

  /// Null on today: past days are not shown.
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
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
            tooltip: 'Previous day',
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
            tooltip: 'Next day',
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
          Text('($count)', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A meeting is shown, never ticked off: no checkbox, no actions.
class _MeetingTile extends StatelessWidget {
  const _MeetingTile({required this.meeting, required this.day});
  final AgendaCalendarItem meeting;
  final String day;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('meeting-${meeting.calendar}-${meeting.uid}-${meeting.start}'),
      leading: const Icon(Icons.event),
      title: Text(meeting.title),
      subtitle: Text(meeting.when(day)),
      trailing: _StatusBadge(label: meeting.calendar),
    );
  }
}

/// A routine due: a recurring one's day or a one-off task in its window.
/// Swiping skips it; the expanded row lists its steps and ticks it off.
class _RoutineItemTile extends StatelessWidget {
  const _RoutineItemTile({
    required this.item,
    required this.onSkip,
    required this.onComplete,
  });
  final AgendaRoutineItem item;
  final VoidCallback onSkip;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final window = item.dueWindow;
    return Dismissible(
      key: Key('routine-dismiss-${item.routineId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.orange,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Text('Skip', style: TextStyle(color: Colors.white)),
      ),
      confirmDismiss: (_) async {
        onSkip();
        return false;
      },
      child: ExpansionTile(
        key: Key('routine-item-${item.routineId}'),
        leading: item.overdue
            ? const Icon(Icons.warning, color: Colors.orange)
            : Icon(
                item.isOneOff ? Icons.task_alt : Icons.repeat,
                color: Colors.grey,
              ),
        title: Text(item.routineName),
        subtitle: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.startTime != null) Text(item.startTime!),
            _StatusBadge(label: item.isOneOff ? 'task' : 'routine'),
            if (item.isOneOff && window != null)
              Text(
                window.describeFrom(item.scheduledFor),
                key: Key('routine-window-${item.routineId}'),
              )
            else if (item.overdue)
              Text(
                'since ${item.scheduledFor}',
                key: Key('routine-since-${item.routineId}'),
              ),
          ],
        ),
        children: [
          ...item.steps.map(
            (t) => ListTile(
              dense: true,
              leading: const Icon(Icons.subdirectory_arrow_right, size: 16),
              title: Text(t.text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  key: Key('routine-complete-${item.routineId}'),
                  onPressed: onComplete,
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
                OutlinedButton.icon(
                  key: Key('routine-skip-${item.routineId}'),
                  onPressed: onSkip,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Skip'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tick of the day: done or skipped, at what hour, for which day when it
/// was not this one, with Undo.
class _TickedTile extends StatelessWidget {
  const _TickedTile({
    required this.item,
    required this.day,
    required this.onUndo,
  });
  final AgendaTickedItem item;
  final String day;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final skipped = item.status == OccurrenceStatus.skipped;
    final time = item.time;
    return ListTile(
      key: Key('ticked-${item.routineId}-${item.scheduledFor}'),
      leading: Icon(
        skipped ? Icons.skip_next : Icons.check,
        color: Colors.grey,
      ),
      title: Text(item.routineName),
      subtitle: Text(
        [
          skipped ? 'skipped' : 'done',
          ?time,
          if (item.scheduledFor != day) 'for ${item.scheduledFor}',
        ].join(' · '),
      ),
      trailing: TextButton(
        key: Key('ticked-undo-${item.routineId}-${item.scheduledFor}'),
        onPressed: onUndo,
        child: const Text('Undo'),
      ),
    );
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
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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
