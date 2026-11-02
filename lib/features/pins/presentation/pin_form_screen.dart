import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/features/pins/domain/pin_draft_store.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';

/// One form for a new pin and for an edit. Pops with the saved [PinDetail], or
/// with nothing when no write was made.
///
/// New pin: the title is proposed by the server for the text, until the owner
/// types one. A failed proposal blocks nothing. Edit: [pin] fills the form, and
/// only the changed fields are sent. A failed or refused save keeps both fields.
///
/// Unsaved fields stay in a draft on this device until a save succeeds or the
/// draft is discarded. Nothing reaches the server before Save: every edit there
/// is a new version with a new id.
class PinFormScreen extends ConsumerStatefulWidget {
  const PinFormScreen({super.key, this.pin, this.initialText});

  /// The pin to edit; null for a new pin.
  final PinDetail? pin;

  /// The starting text of a new pin.
  final String? initialText;

  /// How long the text must stay unchanged before a title is proposed.
  static const proposalDelay = Duration(milliseconds: 800);

  /// How long the fields must stay unchanged before the draft is written.
  static const draftDelay = Duration(milliseconds: 500);

  @override
  ConsumerState<PinFormScreen> createState() => _PinFormScreenState();
}

class _PinFormScreenState extends ConsumerState<PinFormScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _text;
  late final TextEditingController _title;
  late final PinDraftStore _drafts;

  Timer? _proposalTimer;
  Timer? _draftTimer;

  /// Grows with every change of the text, so only the answer for the current
  /// text is taken.
  int _proposalRound = 0;
  bool _proposing = false;
  bool _proposalFailed = false;
  bool _titleTyped = false;
  bool _saving = false;
  String? _topicLabel;
  List<String> _aliases = const [];

  /// The fields stay read-only until the draft is read, so typing cannot race
  /// the restore.
  bool _draftChecked = false;
  bool _draftRestored = false;

  /// Set after a save: no draft may be written behind it.
  bool _draftDone = false;

  /// The server no longer takes this version: its draft has no future.
  bool _stale = false;

  bool get _isEdit => widget.pin != null;

  String get _startingText => widget.pin?.text ?? widget.initialText ?? '';
  String get _startingTitle => widget.pin?.pinName ?? '';

  bool get _canSave =>
      _draftChecked &&
      !_saving &&
      _text.text.trim().isNotEmpty &&
      _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _startingText);
    _title = TextEditingController(text: _startingTitle);
    _drafts = ref.read(pinDraftStoreProvider);
    WidgetsBinding.instance.addObserver(this);
    _restoreDraft();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proposalTimer?.cancel();
    _closeDraft();
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _writeDraft();
  }

  Future<void> _restoreDraft() async {
    PinDraft? draft;
    try {
      draft = await _drafts.load(widget.pin?.recordId);
    } catch (_) {
      // A draft that cannot be read must not block the form.
    }
    if (!mounted) return;
    setState(() {
      _draftChecked = true;
      if (draft == null) return;
      _draftRestored = true;
      _title.text = draft.title;
      _titleTyped = draft.titleTyped;
      _topicLabel = draft.topicLabel;
      _aliases = draft.aliases;
      _text.text = _joined(draft.text, widget.initialText);
    });
    if (!_titleTyped) _proposeNow();
  }

  /// Text brought to the form joins the draft instead of replacing it.
  String _joined(String draft, String? brought) {
    if (brought == null || brought.trim().isEmpty) return draft;
    if (draft.trim().isEmpty) return brought;
    return '$draft\n\n$brought';
  }

  void _closeDraft() {
    if (_stale) {
      _draftTimer?.cancel();
      _removeDraft();
    } else {
      _writeDraft();
    }
  }

  void _discardDraft() {
    _draftTimer?.cancel();
    _proposalTimer?.cancel();
    _proposalRound++;
    _removeDraft();
    setState(() {
      _draftRestored = false;
      _text.text = _startingText;
      _title.text = _startingTitle;
      _titleTyped = false;
      _proposing = false;
      _proposalFailed = false;
      _topicLabel = null;
      _aliases = const [];
    });
    _proposeNow();
  }

  void _scheduleDraftWrite() {
    _draftTimer?.cancel();
    _draftTimer = Timer(PinFormScreen.draftDelay, _writeDraft);
  }

  void _writeDraft() {
    _draftTimer?.cancel();
    if (!_draftChecked || _draftDone) return;
    final title = _title.text;
    final text = _text.text;
    final pin = widget.pin;
    final titleLeft = title.trim().isNotEmpty && (pin != null || _titleTyped);
    final nothingToKeep = text.trim().isEmpty && !titleLeft;
    // Save trims the title, so spaces alone are no change.
    final unchanged =
        pin != null && title.trim() == pin.pinName && text == pin.text;
    if (nothingToKeep || unchanged) {
      _removeDraft();
      return;
    }
    // A draft is a safety net: a failed write must not disturb the form.
    _drafts
        .save(
          pin?.recordId,
          PinDraft(
            title: title,
            text: text,
            titleTyped: _titleTyped,
            topicLabel: _topicLabel,
            aliases: _aliases,
          ),
        )
        .catchError((Object _) {});
  }

  void _removeDraft() {
    _drafts.remove(widget.pin?.recordId).catchError((Object _) {});
  }

  void _proposeNow() {
    if (_isEdit || _text.text.trim().isEmpty) return;
    setState(() => _proposing = true);
    _propose(++_proposalRound, _text.text);
  }

  void _onTextChanged(String text) {
    setState(() {});
    _scheduleDraftWrite();
    if (_isEdit) return;
    _proposalTimer?.cancel();
    final round = ++_proposalRound;
    _topicLabel = null;
    _aliases = const [];
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
      _scheduleDraftWrite();
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
      _draftDone = true;
      _draftTimer?.cancel();
      _removeDraft();
      if (!mounted) return;
      context.pop(saved.pin);
    } catch (e) {
      final gone = (e is PinRefusedException && e.isStale) ||
          e is PinNotFoundException;
      _stale = _stale || gone;
      if (!mounted) return;
      setState(() => _saving = false);
      final reason = e is PinsException ? e.message : e.toString();
      // A stale edit cannot be saved from here, and leaving the form drops the
      // text, so the text is offered for copying.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Not saved: $reason'),
            action: gone
                ? SnackBarAction(
                    label: 'Copy text',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: text)),
                  )
                : null,
          ),
        );
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
    // Back during a save would lose the new record_id the caller must follow.
    return PopScope(
      canPop: !_saving,
      // At once, not at dispose: the next form may open during the transition.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closeDraft();
      },
      child: Scaffold(
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
              if (_draftRestored)
                Row(
                  key: const Key('pin-form-draft'),
                  children: [
                    const Expanded(child: Text('Draft restored')),
                    TextButton(
                      key: const Key('pin-form-draft-discard'),
                      onPressed: _saving ? null : _discardDraft,
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              TextField(
                key: const Key('pin-form-title'),
                controller: _title,
                enabled: !_saving,
                readOnly: !_draftChecked,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Title',
                  helperText: _titleHelper(),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => _titleTyped = value.isNotEmpty);
                  _scheduleDraftWrite();
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  key: const Key('pin-form-text'),
                  controller: _text,
                  enabled: !_saving,
                  readOnly: !_draftChecked,
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
      ),
    );
  }
}
