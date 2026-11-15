import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/widgets/glass.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/providers/agent_turns_provider.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_days.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';
import 'package:voice_agent/features/diet/presentation/meal_correction_sheet.dart';

/// A day of the diet (workspace discussion 2026-11-va-meals-dashboard, 05 §1):
/// what is left with the warning, the meals eaten (a tap corrects one), the
/// menu not eaten yet (one tap logs it), and ‹ › to the days around.
///
/// [field] is the conversation field the app puts at the bottom.
class DietDayScreen extends ConsumerStatefulWidget {
  const DietDayScreen({super.key, this.day, this.field});

  /// YYYY-MM-DD; null is today.
  final String? day;
  final Widget? field;

  @override
  ConsumerState<DietDayScreen> createState() => _DietDayScreenState();
}

class _DietDayScreenState extends ConsumerState<DietDayScreen> {
  late DateTime _day = widget.day == null ? DateTime.now() : parseDay(widget.day!);
  DietDay? _view;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final v = await ref.read(dietRepositoryProvider).day(dayKey(_day));
      if (mounted) setState(() {_view = v; _error = null; _loading = false;});
    } on Object catch (e) {
      if (mounted) setState(() {_error = '$e'; _loading = false;});
    }
  }

  void _move(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _view = null;
    });
    unawaited(_load());
  }

  Future<void> _run(Future<void> Function() write, String said) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await write();
      messenger.showSnackBar(SnackBar(content: Text(said)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // A turn of the agent (a meal said) and a card's correction or undo
    // change the day: read it again (ADR-NET-009).
    ref.listen<int>(agentTurnsProvider, (_, _) => unawaited(_load()));
    ref.listen<int>(dietChangedProvider, (_, _) => unawaited(_load()));
    final now = DateTime.now();
    final isToday = dayKey(_day) == dayKey(now);
    final isPast = _day.isBefore(DateTime(now.year, now.month, now.day));
    final view = _view;
    final warned = view != null && view.warning.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Jedzenie · ${dayLabel(_day, today: now)}'),
        actions: [
          GlassIconButton(
            key: const Key('diet-prev-day'),
            icon: Icons.chevron_left,
            tooltip: 'Dzień wcześniej',
            onPressed: () => _move(-1),
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            key: const Key('diet-next-day'),
            icon: Icons.chevron_right,
            tooltip: 'Dzień później',
            onPressed: isToday ? null : () => _move(1),
          ),
          PopupMenuButton<String>(
            key: const Key('diet-more'),
            onSelected: (route) async {
              await context.push(route);
              unawaited(_load());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '/diet/menu', child: Text('Jadłospis')),
              PopupMenuItem(value: '/diet/own-meals', child: Text('Własne posiłki')),
              PopupMenuItem(value: '/diet/target', child: Text('Cel')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: view == null
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(_error ?? ''),
                              ),
                      ),
                    ])
                  : ListView(
                      key: const Key('diet-day-list'),
                      children: [
                        _DayCard(
                          view: view,
                          warned: warned,
                          targetLine: view.target == null ? null : _targetLine(view),
                          onTap: view.target == null
                              ? () async {
                                  await context.push('/diet/target');
                                  unawaited(_load());
                                }
                              : null,
                        ),
                        const _Heading('ZJEDZONE'),
                        if (view.meals.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            child: Text('Nic jeszcze nie zapisane'),
                          ),
                        // Eaten and planned as glass lists (off-roadmap S3).
                        if (view.meals.isNotEmpty)
                          GlassList(children: [
                        for (final m in view.meals)
                          ListTile(
                            key: Key('diet-meal-${m.id}'),
                            dense: true,
                            leading: SizedBox(width: 48, child: Text(m.time)),
                            title: Text(m.name),
                            trailing: Text(m.estimate.label),
                            onTap: isPast
                                ? null
                                : () async {
                                    final changed = await showMealCorrection(context, m);
                                    if (changed) unawaited(_load());
                                  },
                          ),
                          ]),
                        if (view.planned.isNotEmpty) const _Heading('W PLANIE'),
                        if (view.planned.isNotEmpty)
                          GlassList(children: [
                        for (final e in view.planned)
                          ListTile(
                            key: Key('diet-planned-${e.id}'),
                            dense: true,
                            title: Text('${slotLabel(e.slot)}: ${e.name}'),
                            subtitle: Text('${e.estimate.kcal} kcal'),
                            trailing: isToday
                                ? OutlinedButton(
                                    key: Key('diet-eat-${e.id}'),
                                    onPressed: () => _run(
                                      () => ref.read(dietRepositoryProvider).eatPlanned(e.id),
                                      'Zapisane: ${e.name}',
                                    ),
                                    child: const Text('Zjedzone'),
                                  )
                                : null,
                          ),
                          ]),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ),
          if (isToday && widget.field != null) widget.field!,
        ],
      ),
    );
  }

  static String _targetLine(DietDay v) {
    final t = v.target!;
    final parts = <String>[
      if (v.warning == 'low') 'mniej niż zapas ${t.reserveKcal}',
      'cel ${t.range}',
      if (t.proteinMin != null) 'białko ${(v.eaten.proteinG ?? 0).round()} z ${t.proteinMin} g',
    ];
    return parts.join(' · ');
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
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

/// The day on one glass card: what is eaten as Dziś's large number against
/// the target's top, the bar, and the day's line (off-roadmap S3); under the
/// reserve or over the target it takes the warning's container.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.view,
    required this.warned,
    required this.targetLine,
    required this.onTap,
  });

  final DietDay view;
  final bool warned;
  final String? targetLine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: warned ? colors.onWarningContainer : theme.colorScheme.onSurfaceVariant,
    );
    final target = view.target;
    return GlassCard(
      key: const Key('diet-line'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      fill: warned ? colors.warningContainer.withValues(alpha: 0.85) : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (target != null) ...[
            Text('Zjedzone', style: muted),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // It counts to a new value (off-roadmap S5).
                CountingNumber(
                  view.eaten.kcal,
                  textKey: const Key('diet-eaten-kcal'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 58,
                    height: 1,
                    letterSpacing: -2,
                    color: warned ? colors.onWarningContainer : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text('z ${target.kcalMax} kcal', style: muted),
              ],
            ),
            if (target.kcalMax > 0)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: GlassBar(
                  fraction: (view.eaten.kcal / target.kcalMax).clamp(0.0, 1.0),
                  warned: warned,
                ),
              ),
            const SizedBox(height: 12),
          ],
          Text(
            view.line,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: warned ? colors.onWarningContainer : null,
            ),
          ),
          if (targetLine != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(targetLine!, style: muted),
            ),
        ],
      ),
    );
  }
}
