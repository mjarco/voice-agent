import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/presentation/matter_dialogs.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';

/// Opens a new matter: a title, optional keywords and a next step. Pops with
/// the saved [MatterDetail] (`core/models/matter.dart`).
class MatterFormScreen extends ConsumerStatefulWidget {
  const MatterFormScreen({super.key});

  @override
  ConsumerState<MatterFormScreen> createState() => _MatterFormScreenState();
}

class _MatterFormScreenState extends ConsumerState<MatterFormScreen> {
  final _title = TextEditingController();
  final _keywords = TextEditingController();
  final _nextStep = TextEditingController();
  bool _saving = false;
  bool _titleMissing = false;

  @override
  void dispose() {
    _title.dispose();
    _keywords.dispose();
    _nextStep.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleMissing = true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref.read(mattersRepositoryProvider).createMatter(
            title: title,
            keywords: _keywords.text.trim(),
            nextStep: _nextStep.text.trim(),
          );
      if (mounted) context.pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMatterError(
        context,
        'otworzyć sprawy',
        e is MattersException ? e.message : e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nowa sprawa'),
        actions: [
          TextButton(
            key: const Key('matter-form-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Otwórz'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('matter-form-title'),
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Tytuł',
              errorText: _titleMissing ? 'Sprawa potrzebuje tytułu' : null,
            ),
            onChanged: (_) {
              if (_titleMissing) setState(() => _titleMissing = false);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('matter-form-keywords'),
            controller: _keywords,
            decoration: const InputDecoration(
              labelText: 'Słowa kluczowe',
              helperText: 'Po nich agent rozpozna sprawę w rozmowie',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('matter-form-next-step'),
            controller: _nextStep,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Następny krok'),
          ),
        ],
      ),
    );
  }
}
