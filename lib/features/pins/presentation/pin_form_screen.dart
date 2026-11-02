import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

/// One form for a new pin and for an edit. Pops with the saved [PinDetail], or
/// with nothing when no write was made.
///
/// New pin: the title is proposed by the server for the text, until the owner
/// types one. A failed proposal blocks nothing. Edit: [pin] fills the form, and
/// only the changed fields are sent. A failed or refused save keeps both fields.
class PinFormScreen extends ConsumerStatefulWidget {
  const PinFormScreen({super.key, this.pin, this.initialText});

  /// The pin to edit; null for a new pin.
  final PinDetail? pin;

  /// The starting text of a new pin.
  final String? initialText;

  /// How long the text must stay unchanged before a title is proposed.
  static const proposalDelay = Duration(milliseconds: 800);

  @override
  ConsumerState<PinFormScreen> createState() => _PinFormScreenState();
}

class _PinFormScreenState extends ConsumerState<PinFormScreen> {
  late final TextEditingController _text;
  late final TextEditingController _title;

  Timer? _proposalTimer;

  /// Grows with every change of the text, so only the answer for the current
  /// text is taken.
  int _proposalRound = 0;
  bool _proposing = false;
  bool _proposalFailed = false;
  bool _titleTyped = false;
  bool _saving = false;
  String? _topicLabel;
  List<String> _aliases = const [];

  bool get _isEdit => widget.pin != null;

  bool get _canSave =>
      !_saving &&
      _text.text.trim().isNotEmpty &&
      _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.pin?.text ?? widget.initialText ?? '',
    );
    _title = TextEditingController(text: widget.pin?.pinName ?? '');
    if (!_isEdit && _text.text.trim().isNotEmpty) {
      _proposalRound++;
      _proposing = true;
      _propose(_proposalRound, _text.text);
    }
  }

  @override
  void dispose() {
    _proposalTimer?.cancel();
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    setState(() {});
    if (_isEdit) return;
    _proposalTimer?.cancel();
    final round = ++_proposalRound;
    if (text.trim().isEmpty) {
      setState(() => _proposing = false);
      return;
    }
    setState(() => _proposing = true);
    _proposalTimer = Timer(
      PinFormScreen.proposalDelay,
      () => _propose(round, text),
    );
  }

  Future<void> _propose(int round, String text) async {
    try {
      final proposal = await ref.read(pinWriterProvider).suggestPinFromText(text);
      if (!mounted || round != _proposalRound) return;
      setState(() {
        _proposing = false;
        _proposalFailed = false;
        _topicLabel = proposal.topicLabel;
        _aliases = proposal.aliases;
        if (!_titleTyped) _title.text = proposal.name;
      });
    } catch (_) {
      if (!mounted || round != _proposalRound) return;
      setState(() {
        _proposing = false;
        _proposalFailed = true;
        _topicLabel = null;
        _aliases = const [];
      });
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final text = _text.text;
    final name = _title.text.trim();
    final pin = widget.pin;
    final writer = ref.read(pinWriterProvider);

    final changedName = pin != null && name != pin.pinName ? name : null;
    final changedText = pin != null && text != pin.text ? text : null;
    if (pin != null && changedName == null && changedText == null) {
      context.pop();
      return;
    }

    _proposalTimer?.cancel();
    _proposalRound++;
    setState(() {
      _saving = true;
      _proposing = false;
    });
    try {
      final saved = pin == null
          ? await writer.createTextPin(
              PinTextCreateRequest(
                text: text,
                name: name,
                topicLabel: _topicLabel,
                aliases: _aliases,
              ),
            )
          : await writer.editPin(
              pin.recordId,
              name: changedName,
              text: changedText,
            );
      if (!mounted) return;
      context.pop(saved.pin);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final reason = e is PinsException ? e.message : e.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Not saved: $reason')));
    }
  }

  String? _titleHelper() {
    if (_proposing) return 'Proposing a title…';
    if (_proposalFailed && _title.text.trim().isEmpty) {
      return 'No proposal, type a title';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit pin' : 'New pin'),
        actions: [
          TextButton(
            key: const Key('pin-form-save'),
            onPressed: _canSave ? _save : null,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              key: const Key('pin-form-title'),
              controller: _title,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Title',
                helperText: _titleHelper(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _titleTyped = value.isNotEmpty),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                key: const Key('pin-form-text'),
                controller: _text,
                enabled: !_saving,
                autofocus: !_isEdit && _text.text.isEmpty,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: _onTextChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
