import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/widgets/glass.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_days.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';

/// The daily target and its warning (05 §5): the target in force with its
/// reserve, the earlier ones, and a new one from a day on.
class TargetScreen extends ConsumerStatefulWidget {
  const TargetScreen({super.key});

  @override
  ConsumerState<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends ConsumerState<TargetScreen> {
  List<DietTarget>? _targets;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final all = await ref.read(dietRepositoryProvider).targets();
      if (mounted) setState(() {_targets = all; _error = null;});
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _change(DietTarget? now) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TargetForm(current: now),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final today = dayKey(DateTime.now());
    final current = targets?.where((t) => t.from.compareTo(today) <= 0).firstOrNull;
    final later = targets?.where((t) => t.from.compareTo(today) > 0).toList() ?? const <DietTarget>[];
    final earlier = targets?.where((t) => t != current && t.from.compareTo(today) <= 0).toList() ?? const <DietTarget>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Cel')),
      body: targets == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : ListView(
              key: const Key('target-list'),
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                // The targets on glass cards (off-roadmap S3).
                GlassList(children: [
                if (current == null)
                  const ListTile(title: Text('Nie masz celu. Ustaw go, a pokażę, ile zostało.'))
                else
                  ListTile(
                    key: const Key('target-current'),
                    title: Text('od ${dayLabel(parseDay(current.from))}   ${current.range}'),
                    subtitle: Text([
                      if (current.proteinMin != null) 'białko ${current.proteinMin} g',
                      current.reserveKcal > 0
                          ? 'ostrzegaj poniżej ${current.reserveKcal} kcal'
                          : 'bez ostrzeżenia',
                    ].join('\n')),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const Key('target-change'),
                    onPressed: () => _change(current),
                    child: Text(current == null ? 'Ustaw cel' : 'Zmień cel'),
                  ),
                ),
                if (later.isNotEmpty)
                  GlassList(children: [
                    for (final t in later)
                      ListTile(dense: true, title: Text('od ${dayLabel(parseDay(t.from))}   ${t.range}'), subtitle: const Text('zaplanowany')),
                  ]),
                if (earlier.isNotEmpty) const SectionLabel('Wcześniej'),
                if (earlier.isNotEmpty)
                  GlassList(children: [
                    for (final t in earlier)
                      ListTile(
                        dense: true,
                        title: Text('od ${dayLabel(parseDay(t.from))}   ${t.range}'),
                        subtitle: Text('zapas ${t.reserveKcal} kcal'),
                      ),
                  ]),
              ],
            ),
    );
  }
}

class _TargetForm extends ConsumerStatefulWidget {
  const _TargetForm({required this.current});

  final DietTarget? current;

  @override
  ConsumerState<_TargetForm> createState() => _TargetFormState();
}

class _TargetFormState extends ConsumerState<_TargetForm> {
  late final _min = TextEditingController(text: '${widget.current?.kcalMin ?? ''}');
  late final _max = TextEditingController(text: '${widget.current?.kcalMax ?? ''}');
  late final _protein = TextEditingController(text: '${widget.current?.proteinMin ?? ''}');
  late final _reserve = TextEditingController(text: '${widget.current?.reserveKcal ?? 600}');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_min, _max, _protein, _reserve]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final max = int.tryParse(_max.text.trim());
    final min = int.tryParse(_min.text.trim()) ?? max;
    final protein = int.tryParse(_protein.text.trim());
    final reserve = int.tryParse(_reserve.text.trim());
    if (max == null || min == null || max <= 0 || min > max) {
      setState(() => _error = 'Zakres kcal: od ≤ do');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).setTarget(kcalMin: min, kcalMax: max, proteinMin: protein, reserveKcal: reserve);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() {_error = '$e'; _busy = false;});
    }
  }

  Widget _field(TextEditingController c, String label, Key key) => TextField(
        key: key,
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nowy cel od dziś', style: Theme.of(context).textTheme.titleLarge),
          Row(children: [
            Expanded(child: _field(_min, 'kcal od', const Key('target-min'))),
            const SizedBox(width: 12),
            Expanded(child: _field(_max, 'kcal do', const Key('target-max'))),
          ]),
          _field(_protein, 'białko, g (puste: bez)', const Key('target-protein')),
          _field(_reserve, 'ostrzegaj poniżej, kcal (0: nigdy)', const Key('target-reserve')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(key: const Key('target-save'), onPressed: _busy ? null : _save, child: const Text('Zapisz')),
        ],
      ),
    );
  }
}
