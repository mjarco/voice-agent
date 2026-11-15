import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/day_story.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';

/// From this hour Dziś shows the day's story (09 §5 of the workspace
/// discussion 2026-11-va-meals-dashboard; ADR-NET-010).
const eveningFromHour = 19;

/// YYYY-MM-DD of [t].
String dayOf(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

const _weekdays = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];
const _months = [
  'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca',
  'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia',
];

/// "sobota, 14 listopada".
String dayTitle(String day) {
  final d = DateTime.tryParse(day);
  if (d == null) return day;
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// The story's block on Dziś: in the evening the narration, what waits to be
/// settled and the way to the timeline; before it, only a line when something
/// waits.
class DayStoryBlock extends ConsumerWidget {
  const DayStoryBlock({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evening = now.hour >= eveningFromHour;
    final day = dayOf(now);
    final key = (day: day, narrate: evening);
    final state = ref.watch(dayStoryProvider(key));
    final story = state.story;
    if (story == null) return const SizedBox.shrink();
    final notifier = ref.read(dayStoryProvider(key).notifier);
    void openDay() => unawaited(context.push('/day/$day'));

    if (!evening) {
      if (story.pending.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Card(
          child: ListTile(
            key: const Key('story-pending-count'),
            leading: const Icon(Icons.inbox_outlined),
            title: Text('Do rozstrzygnięcia: ${story.pending.length}'),
            subtitle: const Text('Odłożone na wieczór'),
            trailing: const Icon(Icons.chevron_right),
            onTap: openDay,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        key: const Key('story-block'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('DZIŚ W SKRÓCIE'),
              if (story.narration != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Text(story.narration!, key: const Key('story-narration'),
                      style: Theme.of(context).textTheme.bodyLarge),
                )
              else if (state.loading)
                const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              if (story.pending.isNotEmpty) ...[
                const SizedBox(height: 12),
                PendingList(story: story, settling: state.settling, onSettle: notifier.settle),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('story-open-day'),
                  onPressed: openDay,
                  child: const Text('Oś dnia ›'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
}

/// What waits to be settled: the words as said, a button per guess and Nic.
class PendingList extends StatelessWidget {
  const PendingList({super.key, required this.story, required this.settling, required this.onSettle});

  final DayStory story;
  final Set<String> settling;
  final Future<bool> Function(String id, int? guess) onSettle;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Future<void> settle(String id, int? guess) async {
      final ok = await onSettle(id, guess);
      if (!ok) messenger?.showSnackBar(const SnackBar(content: Text('Nie udało się. Spróbuj jeszcze raz.')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('DO ROZSTRZYGNIĘCIA · ${story.pending.length}'),
        for (final p in story.pending)
          Padding(
            key: Key('story-pending-${p.id}'),
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('„${p.said}”  ${p.day == story.day ? p.at : '${dayTitle(p.day)} ${p.at}'}'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < p.guesses.length; i++)
                      OutlinedButton(
                        key: Key('story-guess-${p.id}-$i'),
                        onPressed: settling.contains(p.id) ? null : () => unawaited(settle(p.id, i)),
                        child: Text(p.guesses[i]),
                      ),
                    TextButton(
                      key: Key('story-none-${p.id}'),
                      onPressed: settling.contains(p.id) ? null : () => unawaited(settle(p.id, null)),
                      child: const Text('Nic'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A day's story on its own screen (`/day/:date`): the narration, what waits,
/// and the whole timeline, each line opening its thing; the arrows go a day
/// back and forth.
class DayStoryScreen extends ConsumerWidget {
  const DayStoryScreen({super.key, required this.day});

  final String day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (day: day, narrate: true);
    final state = ref.watch(dayStoryProvider(key));
    final notifier = ref.read(dayStoryProvider(key).notifier);
    final story = state.story;
    final d = DateTime.tryParse(day);
    final today = dayOf(DateTime.now());
    void go(int by) {
      if (d == null) return;
      context.pushReplacement('/day/${dayOf(d.add(Duration(days: by)))}');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(dayTitle(day), key: const Key('story-day-title')),
        actions: [
          IconButton(key: const Key('story-prev'), icon: const Icon(Icons.chevron_left),
              tooltip: 'Dzień wcześniej', onPressed: () => go(-1)),
          IconButton(key: const Key('story-next'), icon: const Icon(Icons.chevron_right),
              tooltip: 'Dzień później', onPressed: day.compareTo(today) >= 0 ? null : () => go(1)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (state.error != null)
              Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (story == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else ...[
              if (story.narration != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(story.narration!, key: const Key('story-narration'),
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              if (story.pending.isNotEmpty) ...[
                PendingList(story: story, settling: state.settling, onSettle: notifier.settle),
                const SizedBox(height: 16),
              ],
              const _Label('OŚ DNIA'),
              if (story.timeline.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nic tego dnia.')),
              for (final l in story.timeline)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(l.at, style: Theme.of(context).textTheme.bodySmall),
                  title: Text(l.text),
                  trailing: l.kcal != null ? Text('${l.kcal} kcal') : (l.route != null ? const Icon(Icons.chevron_right) : null),
                  onTap: l.route == null ? null : () => unawaited(context.push(l.route!)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
