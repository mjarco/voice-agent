import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';

/// Opens the correction of a meal (05 §2): kcal with its range, protein and
/// the hour; it sends only what changed. True when the meal was changed or
/// removed.
Future<bool> showMealCorrection(BuildContext context, DietMeal meal) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MealCorrectionSheet(meal: meal),
  );
  return changed ?? false;
}

class _MealCorrectionSheet extends ConsumerStatefulWidget {
  const _MealCorrectionSheet({required this.meal});

  final DietMeal meal;

  @override
  ConsumerState<_MealCorrectionSheet> createState() => _MealCorrectionSheetState();
}

class _MealCorrectionSheetState extends ConsumerState<_MealCorrectionSheet> {
  late final _kcal = TextEditingController(text: '${widget.meal.estimate.kcal}');
  late final _low = TextEditingController(text: '${widget.meal.estimate.low}');
  late final _high = TextEditingController(text: '${widget.meal.estimate.high}');
  late final _protein = TextEditingController(
    text: widget.meal.estimate.proteinG == null ? '' : widget.meal.estimate.proteinG!.round().toString(),
  );
  late final _time = TextEditingController(text: widget.meal.time);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_kcal, _low, _high, _protein, _time]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final e = widget.meal.estimate;
    final kcal = int.tryParse(_kcal.text.trim());
    final low = int.tryParse(_low.text.trim());
    final high = int.tryParse(_high.text.trim());
    final protein = double.tryParse(_protein.text.trim().replaceAll(',', '.'));
    final time = _time.text.trim();
    if (kcal == null || kcal <= 0) {
      setState(() => _error = 'Podaj kcal');
      return;
    }
    if (time.isNotEmpty && !RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time)) {
      setState(() => _error = 'Godzina jako GG:MM');
      return;
    }
    final estimateChanged = kcal != e.kcal || low != e.low || high != e.high || protein != e.proteinG;
    final timeChanged = time.isNotEmpty && time != widget.meal.time;
    if (!estimateChanged && !timeChanged) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).editMeal(
            widget.meal.id,
            kcal: estimateChanged ? kcal : null,
            low: estimateChanged && (low != e.low || high != e.high) ? low : null,
            high: estimateChanged && (low != e.low || high != e.high) ? high : null,
            proteinG: estimateChanged && protein != e.proteinG ? protein : null,
            time: timeChanged ? time.padLeft(5, '0') : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (err) {
      if (mounted) setState(() {_error = '$err'; _busy = false;});
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).removeMeal(widget.meal.id);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (err) {
      if (mounted) setState(() {_error = '$err'; _busy = false;});
    }
  }

  Widget _number(TextEditingController c, String label, {Key? key}) => Expanded(
        child: TextField(
          key: key,
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.meal.name, style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            _number(_kcal, 'kcal', key: const Key('correction-kcal')),
            const SizedBox(width: 12),
            _number(_low, 'od'),
            const SizedBox(width: 12),
            _number(_high, 'do'),
          ]),
          Row(children: [
            _number(_protein, 'białko, g'),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('correction-time'),
                controller: _time,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'godzina'),
              ),
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton(
              key: const Key('correction-save'),
              onPressed: _busy ? null : _save,
              child: const Text('Zapisz'),
            ),
            const SizedBox(width: 12),
            TextButton(
              key: const Key('correction-remove'),
              onPressed: _busy ? null : _remove,
              child: const Text('Usuń'),
            ),
          ]),
        ],
      ),
    );
  }
}
