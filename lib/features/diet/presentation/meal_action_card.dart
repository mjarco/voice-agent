import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/agent_action.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';
import 'package:voice_agent/features/diet/presentation/meal_correction_sheet.dart';

/// The card of a meal a reply logged (workspace discussion
/// 2026-11-va-meals-dashboard, 10 §4; ADR-NET-009): what was logged, its
/// estimate and what is left, with Popraw (the correction of 05 §2) and
/// Cofnij (the meal removed). Either takes the card away and has the day read
/// itself again.
class MealActionCard extends ConsumerStatefulWidget {
  const MealActionCard({super.key, required this.action});

  final AgentAction action;

  @override
  ConsumerState<MealActionCard> createState() => _MealActionCardState();
}

class _MealActionCardState extends ConsumerState<MealActionCard> {
  bool _busy = false;

  AgentAction get _a => widget.action;

  void _done() {
    final actions = ref.read(latestAgentActionsProvider);
    ref.read(latestAgentActionsProvider.notifier).state = [
      for (final a in actions)
        if (a.mealId != _a.mealId) a,
    ];
    ref.read(dietChangedProvider.notifier).state++;
  }

  Future<void> _correct() async {
    final meal = DietMeal(
      id: _a.mealId,
      day: _a.day,
      time: _a.time,
      name: _a.name,
      estimate: DietEstimate(kcal: _a.kcal, low: _a.kcalLow, high: _a.kcalHigh, proteinG: _a.proteinG),
    );
    if (await showMealCorrection(context, meal) && mounted) _done();
  }

  Future<void> _undo() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).removeMeal(_a.mealId);
      if (!mounted) return;
      _done();
      messenger.showSnackBar(SnackBar(content: Text('Cofnięto: ${_a.name}')));
    } on Object catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Nie udało się cofnąć: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estimate = DietEstimate(kcal: _a.kcal, low: _a.kcalLow, high: _a.kcalHigh);
    final left = _a.leftKcal;
    final warned = _a.warning.isNotEmpty;
    return Card(
      key: Key('meal-action-${_a.mealId}'),
      margin: const EdgeInsets.only(top: 6, right: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✓ ${_a.name}${_a.time.isEmpty ? '' : ' · ${_a.time}'}',
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              '${estimate.label} kcal${left == null ? '' : ' · zostało $left'}',
              style: TextStyle(color: warned ? scheme.error : null),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('meal-action-correct-${_a.mealId}'),
                  onPressed: _busy ? null : _correct,
                  child: const Text('Popraw'),
                ),
                TextButton(
                  key: Key('meal-action-undo-${_a.mealId}'),
                  onPressed: _busy ? null : _undo,
                  child: const Text('Cofnij'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
