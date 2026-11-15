import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final now = DateTime.now();
    final isToday = dayKey(_day) == dayKey(now);
    final isPast = _day.isBefore(DateTime(now.year, now.month, now.day));
    final view = _view;
    final scheme = Theme.of(context).colorScheme;
    final warned = view != null && view.warning.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Jedzenie · ${dayLabel(_day, today: now)}'),
        actions: [
          IconButton(
            key: const Key('diet-prev-day'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Dzień wcześniej',
            onPressed: () => _move(-1),
          ),
          IconButton(
            key: const Key('diet-next-day'),
            icon: const Icon(Icons.chevron_right),
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
                        ListTile(
                          key: const Key('diet-line'),
                          tileColor: warned ? scheme.errorContainer : null,
                          title: Text(
                            view.line,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: warned ? scheme.onErrorContainer : null,
                                ),
                          ),
                          subtitle: view.target == null
                              ? null
                              : Text(_targetLine(view)),
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
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text('Nic jeszcze nie zapisane'),
                          ),
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
                        if (view.planned.isNotEmpty) const _Heading('W PLANIE'),
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
