import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/widgets/app_bar_actions.dart';
import 'package:voice_agent/features/today/presentation/day_story_view.dart';
import 'package:voice_agent/features/today/presentation/today_notifier.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';

/// Dziś, the start screen (V1 of the redesign, workspace discussion
/// 2026-11-va-meals-dashboard, 03): the day as personal-agent tells it, each
/// block opening its context, and the conversation field at the bottom.
///
/// [field] is the conversation field; the app puts it here, as features do
/// not import each other.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, this.field, this.clock = DateTime.now});

  final Widget? field;

  /// Now, for the story's block (in tests, a fixed hour).
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todayNotifierProvider);
    final notifier = ref.read(todayNotifierProvider.notifier);
    final view = state.view;

    Future<void> open(String route) async {
      await context.push(route);
      unawaited(notifier.refresh());
    }

    return Scaffold(
      appBar: AppBar(
        // The day's title opens the day's story and, from there, any other day.
        title: GestureDetector(
          onTap: () => unawaited(open('/day/${dayOf(clock())}')),
          child: Text(view?.title ?? 'Dziś', key: const Key('today-title')),
        ),
        actions: [AppBarActions(onReturn: () => unawaited(notifier.refresh()))],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: notifier.refresh,
              child: view == null
                  ? _Empty(state: state, onRetry: notifier.refresh)
                  : ListView(
                      key: const Key('today-list'),
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        if (state.error != null) _ErrorLine(state.error!),
                        DayStoryBlock(now: clock()),
                        _FoodBlock(food: view.food, open: open),
                        _AgendaBlock(agenda: view.agenda, open: open),
                        _MattersBlock(matters: view.matters, open: open),
                        _ShoppingLine(shopping: view.shopping),
                      ],
                    ),
            ),
          ),
          ?field,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state, required this.onRetry});

  final TodayState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: state.error == null
              ? const CircularProgressIndicator()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(state.error!, textAlign: TextAlign.center),
                    ),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Spróbuj jeszcze raz'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

// ── Jedzenie ─────────────────────────────────────────────────────────────────

class _FoodBlock extends StatelessWidget {
  const _FoodBlock({required this.food, required this.open});

  final TodayFood food;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warned = food.warning != FoodWarning.none;
    final next = food.nextMeal;
    final nudge = food.nudge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('JEDZENIE'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: warned ? scheme.errorContainer : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                key: const Key('today-food-line'),
                title: Text(
                  food.line,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: warned ? scheme.onErrorContainer : null,
                      ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(food.hasTarget ? '/diet' : '/diet/target'),
              ),
              if (next != null)
                ListTile(
                  key: const Key('today-next-meal'),
                  dense: true,
                  title: Text('${next.slotLabel} z jadłospisu: ${next.name}'),
                  subtitle: Text('${next.kcal} kcal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open('/diet/menu'),
                ),
              if (nudge != null)
                Padding(
                  key: const Key('today-nudge'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(nudge.text)),
                      TextButton(
                        onPressed: () => open('/diet/menu'),
                        child: const Text('Otwórz jadłospis'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dziś: meetings and tasks ─────────────────────────────────────────────────

class _AgendaBlock extends ConsumerWidget {
  const _AgendaBlock({required this.agenda, required this.open});

  final TodayAgenda agenda;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('DZIŚ'),
        if (agenda.line.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(agenda.line, key: const Key('today-nothing')),
          ),
        for (final item in agenda.items)
          item.isTask ? _TaskRow(item: item, open: open) : _MeetingRow(item: item),
        ListTile(
          key: const Key('today-all-agenda'),
          dense: true,
          title: Text(agenda.moreTasks > 0
              ? 'Cała agenda · jeszcze ${agenda.moreTasks}'
              : 'Cała agenda'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/agenda'),
        ),
      ],
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({required this.item});

  final TodayItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(width: 72, child: Text(item.time)),
      title: Text(item.title),
    );
  }
}

/// A task: right is done, left is skip; a tap opens the task. Undo is the
/// snackbar's.
class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.item, required this.open});

  final TodayItem item;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(todayNotifierProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    Future<bool> act(TodayAction? action, String said) async {
      if (action == null) return false;
      final ok = await notifier.run(action);
      if (ok) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text('$said: ${item.title}'),
          action: item.undo == null
              ? null
              : SnackBarAction(
                  label: 'Cofnij',
                  onPressed: () => unawaited(notifier.run(item.undo!)),
                ),
        ));
      }
      return ok;
    }

    return Dismissible(
      key: Key('today-task-${item.key}'),
      background: _SwipeBackground(
        color: AppColors.of(context).success,
        onColor: AppColors.of(context).onSuccess,
        icon: Icons.check,
        label: 'Zrobione',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeBackground(
        color: scheme.outline,
        onColor: scheme.surface,
        icon: Icons.redo,
        label: 'Pomiń',
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) => direction == DismissDirection.startToEnd
          ? act(item.done, 'Zrobione')
          : act(item.skip, 'Pominięte'),
      onDismissed: (_) => notifier.drop(item.key),
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 72,
          child: Text(
            item.overdue ? '!' : item.time,
            style: item.overdue
                ? TextStyle(color: scheme.error, fontWeight: FontWeight.bold)
                : null,
          ),
        ),
        title: Text(item.title),
        trailing: item.note.isEmpty ? null : Text(item.note),
        onTap: item.routineId.isEmpty ? null : () => open('/routine/${item.routineId}'),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final Color onColor;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: onColor)),
        ],
      ),
    );
  }
}

// ── Sprawy w toku ────────────────────────────────────────────────────────────

class _MattersBlock extends StatelessWidget {
  const _MattersBlock({required this.matters, required this.open});

  final TodayMatters matters;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    if (matters.inProgress == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading('SPRAWY W TOKU · ${matters.inProgress}'),
        for (final m in matters.items)
          ListTile(
            dense: true,
            title: Text(m.title),
            subtitle: m.line.isEmpty ? null : Text(m.line),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open('/matter/${m.id}'),
          ),
        ListTile(
          dense: true,
          title: Text(matters.more > 0 ? 'Wszystkie · jeszcze ${matters.more}' : 'Wszystkie'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/matters'),
        ),
      ],
    );
  }
}

// ── Zakupy ───────────────────────────────────────────────────────────────────

class _ShoppingLine extends StatelessWidget {
  const _ShoppingLine({required this.shopping});

  final TodayShopping shopping;

  @override
  Widget build(BuildContext context) {
    if (shopping.toBuy == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('ZAKUPY'),
        ListTile(
          key: const Key('today-shopping'),
          dense: true,
          title: Text(shopping.line),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/shopping'),
        ),
      ],
    );
  }
}
