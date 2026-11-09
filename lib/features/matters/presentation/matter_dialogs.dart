import 'package:flutter/material.dart';
import 'package:voice_agent/core/models/matter.dart';

/// The owner's answer to a proposed matter: accept it as active, accept it as
/// already closed, or drop it. Shown on the list and on the matter's screen.
class ProposedActions extends StatelessWidget {
  const ProposedActions({
    super.key,
    required this.idSuffix,
    required this.onAccept,
    required this.onDrop,
  });

  /// Makes the buttons' keys unique on a list of several proposals.
  final String idSuffix;
  final void Function(MatterStatus status) onAccept;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton(
            key: Key('matter-accept-$idSuffix'),
            onPressed: () => onAccept(MatterStatus.active),
            child: const Text('Przyjmij'),
          ),
          OutlinedButton(
            key: Key('matter-accept-closed-$idSuffix'),
            onPressed: () => onAccept(MatterStatus.closed),
            child: const Text('Przyjmij jako zamkniętą'),
          ),
          TextButton(
            key: Key('matter-drop-$idSuffix'),
            onPressed: onDrop,
            child: const Text('Odrzuć'),
          ),
        ],
      ),
    );
  }
}

/// "Nie udało się [what]: [message]", the message being the server's own.
void showMatterError(BuildContext context, String what, String? message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('Nie udało się $what: ${message ?? ''}')),
    );
}

Future<bool?> confirmDrop(BuildContext context) => confirmMatterAction(
      context,
      key: const Key('matter-drop-dialog'),
      title: 'Odrzucić sprawę?',
      content: 'Proponowana sprawa zostanie usunięta.',
      action: 'Odrzuć',
    );

/// A yes/no dialog; its confirm button has the key `matter-confirm`.
Future<bool?> confirmMatterAction(
  BuildContext context, {
  Key? key,
  required String title,
  required String content,
  required String action,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: key,
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Anuluj'),
        ),
        TextButton(
          key: const Key('matter-confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
}

/// Asks for a line of text, starting from [initial]. Null when cancelled;
/// an empty string when the owner cleared the field.
Future<String?> askMatterText(
  BuildContext context, {
  required String title,
  String initial = '',
  bool multiline = false,
  String? hint,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TextDialog(
      title: title,
      initial: initial,
      multiline: multiline,
      hint: hint ?? title,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.multiline,
    required this.hint,
  });

  final String title;
  final String initial;
  final bool multiline;

  /// What the field asks for while it is empty; a screen reader reads it too.
  final String hint;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('matter-text-field'),
        controller: _controller,
        autofocus: true,
        minLines: widget.multiline ? 3 : 1,
        maxLines: widget.multiline ? 8 : 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        TextButton(
          key: const Key('matter-text-save'),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}
