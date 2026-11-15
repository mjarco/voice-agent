import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/widgets/app_bar_actions.dart';
import 'package:voice_agent/core/widgets/glass.dart';
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
      body: SafeArea(
        bottom: false,
        child: Column(
        children: [
          // Aurora's header (off-roadmap S2): the day's date over a large
          // "Dziś", the bar's actions as round glass buttons. The date opens
          // the day's story and, from there, any other day.
          _Header(
            title: view?.title ?? '',
            onTitle: () => unawaited(open('/day/${dayOf(clock())}')),
            onReturn: () => unawaited(notifier.refresh()),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: notifier.refresh,
              child: view == null
                  ? _Empty(state: state, onRetry: notifier.refresh)
                  : ListView(
                      key: const Key('today-list'),
                      padding: const EdgeInsets.only(top: 4, bottom: 16),
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onTitle, required this.onReturn});

  final String title;
  final VoidCallback onTitle;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTitle,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: const Key('today-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Dziś',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppBarActions(onReturn: onReturn),
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

// ── Jedzenie ─────────────────────────────────────────────────────────────────

class _FoodBlock extends StatelessWidget {
  const _FoodBlock({required this.food, required this.open});

  final TodayFood food;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final warned = food.warning != FoodWarning.none;
    final next = food.nextMeal;
    final nudge = food.nudge;
    final left = food.leftKcal;
    final max = food.kcalMax;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        GlassCard(
          key: const Key('today-food-line'),
          fill: warned ? colors.warningContainer.withValues(alpha: 0.85) : null,
          onTap: () => open(food.hasTarget ? '/diet' : '/diet/target'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Jedzenie', style: muted)),
                  if (max != null) Text('z $max', style: muted),
                ],
              ),
              if (food.hasTarget && left != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // It counts to a new value (off-roadmap S5).
                    CountingNumber(
                      left,
                      textKey: const Key('today-kcal-left'),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 58,
                        height: 1,
                        letterSpacing: -2,
                        color: warned ? colors.onWarningContainer : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('kcal zostało', style: muted),
                  ],
                ),
                if (max != null && max > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: GlassBar(fraction: ((max - left) / max).clamp(0.0, 1.0), warned: warned),
                  ),
              ],
              // The sentence of personal-agent: the number in words, or the
              // warning under the reserve. With the number shown large, the
              // sentence would only repeat it, so it stays for a warning or
              // when there is no number.
              if (warned || !food.hasTarget || left == null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  food.line,
                  style: warned
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onWarningContainer,
                          fontWeight: FontWeight.w600,
                        )
                      : muted?.copyWith(fontWeight: FontWeight.w400),
                ),
              ),
              if (next != null)
                InkWell(
                  key: const Key('today-next-meal'),
                  onTap: () => open('/diet/menu'),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Następny: ${next.slotLabel.toLowerCase()} · ${next.name} · ${next.kcal}',
                      style: muted?.copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
                ),
              if (nudge != null)
                Padding(
                  key: const Key('today-nudge'),
                  padding: const EdgeInsets.only(top: 4),
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
        const SectionLabel('DZIŚ'),
        GlassList(
          children: [
            if (agenda.line.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(agenda.line, key: const Key('today-nothing')),
              ),
            for (final item in agenda.items)
              item.isTask ? _TaskRow(item: item, open: open) : _MeetingRow(item: item),
            GlassRow(
              key: const Key('today-all-agenda'),
              title: agenda.moreTasks > 0
                  ? 'Cała agenda · jeszcze ${agenda.moreTasks}'
                  : 'Cała agenda',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/agenda'),
            ),
          ],
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
    return GlassRow(leading: GlassPill(item.time), title: item.title);
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
      child: GlassRow(
        leading: item.overdue
            ? const GlassPill('zaległe', warning: true)
            : GlassPill(item.time.isEmpty ? '·' : item.time),
        title: item.title,
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
        SectionLabel('SPRAWY W TOKU · ${matters.inProgress}'),
        GlassList(
          children: [
            for (final m in matters.items)
              GlassRow(
                title: m.title,
                subtitle: m.line,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open('/matter/${m.id}'),
              ),
            GlassRow(
              title: matters.more > 0 ? 'Wszystkie · jeszcze ${matters.more}' : 'Wszystkie',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/matters'),
            ),
          ],
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
        const SectionLabel('ZAKUPY'),
        GlassList(
          children: [
            GlassRow(
              key: const Key('today-shopping'),
              title: shopping.line,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/shopping'),
            ),
          ],
        ),
      ],
    );
  }
}
