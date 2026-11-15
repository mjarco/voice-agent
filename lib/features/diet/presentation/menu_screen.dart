import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_days.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';

/// The menu (05 §3): the days from today on, by mealtime. An empty day says
/// so and offers to place an own meal; a tap on an entry takes it off. Laying
/// a menu out with the agent goes through the conversation field of Dziś.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  /// How many days ahead the menu shows, today included.
  static const days = 7;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  List<DietMenuEntry>? _entries;
  String? _error;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final from = dayKey(_today);
      final to = dayKey(_today.add(const Duration(days: MenuScreen.days - 1)));
      final all = await ref.read(dietRepositoryProvider).menu(from, to);
      if (mounted) setState(() {_entries = all; _error = null;});
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _write(Future<void> Function() w, String said) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await w();
      messenger.showSnackBar(SnackBar(content: Text(said)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  Future<void> _add(String day) async {
    final repo = ref.read(dietRepositoryProvider);
    final List<DietOwnMeal> own;
    try {
      own = await repo.ownMeals();
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    if (own.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nie masz jeszcze własnych posiłków. Powiedz agentowi, co zapamiętać.'),
      ));
      return;
    }
    final picked = await showDialog<(String, DietOwnMeal)>(
      context: context,
      builder: (_) => _AddDialog(own: own),
    );
    if (picked == null) return;
    await _write(
      () => repo.planOwnMeal(day: day, slot: picked.$1, ownMealId: picked.$2.id),
      'W jadłospisie: ${picked.$2.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadłospis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: 'Własne posiłki',
            onPressed: () => context.push('/diet/own-meals'),
          ),
        ],
      ),
      body: entries == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const Key('menu-list'),
                children: [
                  for (var i = 0; i < MenuScreen.days; i++)
                    ..._day(_today.add(Duration(days: i)), entries),
                ],
              ),
            ),
    );
  }

  List<Widget> _day(DateTime d, List<DietMenuEntry> all) {
    final key = dayKey(d);
    final entries = [for (final e in all) if (e.day == key) e]
      ..sort((a, b) => slotOrder(a.slot).compareTo(slotOrder(b.slot)));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dayLabel(d, today: _today).toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.2),
              ),
            ),
            TextButton.icon(
              key: Key('menu-add-$key'),
              onPressed: () => _add(key),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj'),
            ),
          ],
        ),
      ),
      if (entries.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('nic nie zaplanowane'),
        ),
      for (final e in entries)
        ListTile(
          key: Key('menu-entry-${e.id}'),
          dense: true,
          leading: SizedBox(width: 110, child: Text(slotLabel(e.slot))),
          title: Text(e.name),
          trailing: Text(e.eaten ? '✓ zjedzone' : '${e.estimate.kcal}'),
          onTap: e.eaten
              ? null
              : () async {
                  final off = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(e.name),
                      content: const Text('Zdjąć z jadłospisu?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nie')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Zdejmij')),
                      ],
                    ),
                  );
                  if (off == true) {
                    await _write(() => ref.read(dietRepositoryProvider).unplan(e.id), 'Zdjęte: ${e.name}');
                  }
                },
        ),
    ];
  }
}

class _AddDialog extends StatefulWidget {
  const _AddDialog({required this.own});

  final List<DietOwnMeal> own;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  String _slot = 'lunch';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dodaj do jadłospisu'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              key: const Key('menu-add-slot'),
              value: _slot,
              isExpanded: true,
              items: [
                for (final (slot, label) in dietSlots) DropdownMenuItem(value: slot, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _slot = v ?? _slot),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in widget.own)
                    ListTile(
                      title: Text(m.name),
                      subtitle: Text('${m.estimate.kcal} kcal'),
                      onTap: () => Navigator.pop(context, (_slot, m)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
