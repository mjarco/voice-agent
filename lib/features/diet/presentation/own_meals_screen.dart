import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';

/// Own meals (05 §4): each with its portion, estimate and ingredients folded
/// under it. Adding one goes better by voice; the screen shows and removes.
class OwnMealsScreen extends ConsumerStatefulWidget {
  const OwnMealsScreen({super.key});

  @override
  ConsumerState<OwnMealsScreen> createState() => _OwnMealsScreenState();
}

class _OwnMealsScreenState extends ConsumerState<OwnMealsScreen> {
  List<DietOwnMeal>? _meals;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final all = await ref.read(dietRepositoryProvider).ownMeals();
      if (mounted) setState(() {_meals = all; _error = null;});
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _remove(DietOwnMeal m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(m.name),
        content: const Text('Usunąć z własnych posiłków?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nie')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dietRepositoryProvider).removeOwnMeal(m.id);
      messenger.showSnackBar(SnackBar(content: Text('Usunięte: ${m.name}')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final meals = _meals;
    return Scaffold(
      appBar: AppBar(title: const Text('Własne posiłki')),
      body: meals == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : meals.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Brak. Powiedz agentowi, np. „zapamiętaj owsiankę: …”.', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  key: const Key('own-meals-list'),
                  children: [
                    for (final m in meals)
                      ExpansionTile(
                        key: Key('own-meal-${m.id}'),
                        title: Text(m.name),
                        subtitle: Text([
                          if (m.portion.isNotEmpty) m.portion,
                          '${m.estimate.label} kcal',
                        ].join(' · ')),
                        children: [
                          for (final i in m.ingredients) ListTile(dense: true, title: Text(i.label)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: () => _remove(m), child: const Text('Usuń')),
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}
