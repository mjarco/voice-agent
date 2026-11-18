import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';

/// Own meals to pick one eaten now, from the diet's day (workspace assignment
/// 2026-11-18-own-meal-eaten): a tap on a meal returns it, nothing is written
/// here. Null when closed without a pick.
Future<DietOwnMeal?> pickOwnMeal(BuildContext context) => showModalBottomSheet<DietOwnMeal>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _OwnMealPicker(),
    );

class _OwnMealPicker extends ConsumerStatefulWidget {
  const _OwnMealPicker();

  @override
  ConsumerState<_OwnMealPicker> createState() => _OwnMealPickerState();
}

class _OwnMealPickerState extends ConsumerState<_OwnMealPicker> {
  List<DietOwnMeal>? _meals;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await ref.read(dietRepositoryProvider).ownMeals();
      if (mounted) setState(() => _meals = all);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final meals = _meals;
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Zjedzone teraz', style: theme.textTheme.titleMedium),
            ),
            if (meals == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
              )
            else if (meals.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak własnych posiłków. Powiedz agentowi, np. „zapamiętaj owsiankę: …”.'),
              )
            else
              Flexible(
                child: ListView(
                  key: const Key('own-meal-picker'),
                  shrinkWrap: true,
                  children: [
                    for (final m in meals)
                      ListTile(
                        key: Key('own-meal-pick-${m.id}'),
                        title: Text(m.name),
                        subtitle: m.portion.isEmpty ? null : Text(m.portion),
                        trailing: Text('${m.estimate.label} kcal'),
                        onTap: () => Navigator.pop(context, m),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
