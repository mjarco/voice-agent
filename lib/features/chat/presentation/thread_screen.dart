import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/widgets/agent_markdown_style.dart';
import 'package:voice_agent/core/widgets/shopping_proposal_card.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';

class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref
        .read(threadNotifierProvider(widget.conversationId).notifier)
        .refreshProposals();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Pin flow for an agent message (proposal 046): suggest a name, confirm
  /// in a dialog, then create. The notifier owns the network calls and the
  /// in-flight / pinned sets; this method only drives the dialog and SnackBars.
  Future<void> _startPin(ConversationEvent event) async {
    final notifier =
        ref.read(threadNotifierProvider(widget.conversationId).notifier);
    final messenger = ScaffoldMessenger.of(context);

    final PinSuggestion? suggestion;
    try {
      suggestion = await notifier.beginPin(event.conversationId, event.eventId);
    } catch (e) {
      // Not only Exception: a malformed answer throws a TypeError, which must
      // not pass silently.
      messenger.showSnackBar(
        SnackBar(content: Text('Could not prepare pin: $e')),
      );
      return;
    }
    // Already pinned or a flow is already running for this message.
    if (suggestion == null) return;
    if (!mounted) return;
    final picked = suggestion;

    final confirmed = await showDialog<_PinConfirmation>(
      context: context,
      builder: (_) => _PinConfirmDialog(suggestion: picked),
    );
    if (confirmed == null) {
      notifier.cancelPin(event.eventId);
      return;
    }

    try {
      final created = await notifier.confirmPin(
        event.conversationId,
        event.eventId,
        name: confirmed.name,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Pinned as "${created.pin.pinName}"'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => context.push('/pins'),
          ),
        ),
      );
    } catch (e) {
      // A TypeError from a malformed answer still gets its SnackBar.
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not pin: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(threadNotifierProvider(widget.conversationId));
    final notifier =
        ref.read(threadNotifierProvider(widget.conversationId).notifier);

    final String title;
    final List<ConversationEvent> events;
    final List<ShoppingProposalRow> proposals;
    final List<ModelInfo> models;
    final List<BackendInfo> backends;
    final String? selectedModel;
    final String? selectedBackend;
    final bool isStreaming;
    final String? pendingMessage;
    final String? toolProgress;
    final bool isClosed;

    switch (state) {
      case ThreadLoading():
        return Scaffold(
          appBar: AppBar(title: const Text('Loading\u2026')),
          body: const Center(child: CircularProgressIndicator()),
        );

      case ThreadError(message: final msg, previousState: final prev):
        return Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(msg),
                const SizedBox(height: 16),
                if (prev != null)
                  ElevatedButton(
                    key: const Key('thread-retry-button'),
                    onPressed: notifier.load,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        );

      case ThreadEmpty(
          models: final m,
          backends: final b,
          selectedModel: final sm,
          selectedBackend: final sb,
        ):
        title = 'New Chat';
        events = const [];
        proposals = const [];
        models = m;
        backends = b;
        selectedModel = sm;
        selectedBackend = sb;
        isStreaming = false;
        pendingMessage = null;
        toolProgress = null;
        isClosed = false;

      case ThreadLoaded(
          conversation: final conv,
          events: final e,
          proposals: final p,
          models: final m,
          backends: final b,
          selectedModel: final sm,
          selectedBackend: final sb,
        ):
        title = conv.firstMessagePreview ?? 'New Chat';
        events = e;
        proposals = p;
        models = m;
        backends = b;
        selectedModel = sm;
        selectedBackend = sb;
        isStreaming = false;
        pendingMessage = null;
        toolProgress = null;
        isClosed = conv.status == ConversationStatus.closed;

      case ThreadStreaming(
          conversation: final conv,
          events: final e,
          proposals: final p,
          models: final m,
          backends: final b,
          selectedModel: final sm,
          selectedBackend: final sb,
          pendingUserMessage: final pm,
          toolProgress: final tp,
        ):
        title = conv?.firstMessagePreview ?? 'New Chat';
        events = e;
        proposals = p;
        models = m;
        backends = b;
        selectedModel = sm;
        selectedBackend = sb;
        isStreaming = true;
        pendingMessage = pm;
        toolProgress = tp;
        isClosed = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          _ModelBackendPicker(
            models: models,
            backends: backends,
            selectedModel: selectedModel,
            selectedBackend: selectedBackend,
            onSelectModel: notifier.selectModel,
            onSelectBackend: notifier.selectBackend,
          ),
          IconButton(
            key: const Key('thread-settings-icon'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              key: const Key('thread-message-list'),
              reverse: true,
              children: [
                if (isStreaming) _TypingIndicator(toolProgress: toolProgress),
                if (pendingMessage != null)
                  _MessageBubble(
                    key: const Key('thread-pending-message'),
                    content: pendingMessage,
                    role: EventRole.user,
                    pending: true,
                  ),
                ...(() {
                  final reversed = events.reversed.toList();
                  final cards = _proposalsByAnchor(events, proposals);
                  final widgets = <Widget>[];
                  for (var i = 0; i < reversed.length; i++) {
                    final event = reversed[i];
                    // The list is reversed: what goes first shows lowest, so a
                    // card comes before its anchor and the newest card first.
                    for (final row
                        in (cards[event.eventId] ?? const []).reversed) {
                      widgets.add(ShoppingProposalCard(
                        key: Key('shopping-proposal-${row.proposal.id}'),
                        row: row,
                        onAccept: () => notifier.answerProposal(
                          row.proposal.id,
                          accept: true,
                        ),
                        onSkip: () => notifier.answerProposal(
                          row.proposal.id,
                          accept: false,
                        ),
                      ));
                    }
                    final canPin = event.role == EventRole.agent &&
                        event.conversationId.isNotEmpty;
                    widgets.add(_MessageBubble(
                      key: Key('thread-event-${event.eventId}'),
                      content: event.content,
                      role: event.role,
                      eventId: event.eventId,
                      canPin: canPin,
                      pinned: canPin && notifier.isPinned(event.eventId),
                      pinInFlight:
                          canPin && notifier.isPinInFlight(event.eventId),
                      onPin: canPin ? () => _startPin(event) : null,
                    ));
                  }
                  return widgets;
                })(),
              ],
            ),
          ),
          if (isClosed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Conversation closed',
                key: const Key('thread-closed-label'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
          _InputBar(
            controller: _textController,
            canSend: !isStreaming && !isClosed,
            isStreaming: isStreaming,
            onSend: (text) {
              notifier.send(text);
              _textController.clear();
            },
            onCancel: notifier.cancelStream,
          ),
        ],
      ),
    );
  }
}

/// The event each card sits under: the reply to the message that proposed it,
/// or the message itself when no reply followed. A proposal whose message is not
/// in the thread is not shown.
Map<String, List<ShoppingProposalRow>> _proposalsByAnchor(
  List<ConversationEvent> events,
  List<ShoppingProposalRow> rows,
) {
  final indexById = {
    for (var i = 0; i < events.length; i++) events[i].eventId: i,
  };
  final anchors = <String, List<ShoppingProposalRow>>{};
  for (final row in rows) {
    final index = indexById[row.proposal.userEventId];
    if (index == null) continue;
    final next = index + 1 < events.length ? events[index + 1] : null;
    final anchor = next?.role == EventRole.agent ? next! : events[index];
    anchors.putIfAbsent(anchor.eventId, () => []).add(row);
  }
  return anchors;
}

final _ssmlLangStrip =
    RegExp(r'<lang xml:lang="[a-z]{2,3}(?:-[A-Z]{2,4})?">|</lang>');

String _stripSsmlLang(String text) => text.replaceAll(_ssmlLangStrip, '');

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.content,
    required this.role,
    this.pending = false,
    this.eventId,
    this.canPin = false,
    this.pinned = false,
    this.pinInFlight = false,
    this.onPin,
  });

  final String content;
  final EventRole role;
  final bool pending;

  /// Backend event id — present only for persisted messages (proposal 046).
  final String? eventId;

  /// Whether the pin affordance is shown. True only for agent messages that
  /// have a real server identity (an [eventId] + conversation id).
  final bool canPin;
  final bool pinned;
  final bool pinInFlight;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isUser = role == EventRole.user;

    final bubbleColor = isUser
        ? cs.primary.withAlpha(pending ? 128 : 255)
        : cs.surfaceContainerHighest;
    final fgColor = isUser ? cs.onPrimary : cs.onSurface;

    final Widget body;
    if (isUser) {
      body = SelectableText(
        content,
        key: Key('bubble-$role'),
        style: TextStyle(color: fgColor, height: 1.4),
      );
    } else {
      body = MarkdownBody(
        key: Key('bubble-$role'),
        data: _stripSsmlLang(content),
        selectable: true,
        styleSheet: agentMarkdownStyle(theme),
        softLineBreak: true,
      );
    }

    final Widget bubbleContent;
    if (canPin) {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          Align(
            alignment: Alignment.centerRight,
            child: _PinButton(
              eventId: eventId,
              pinned: pinned,
              inFlight: pinInFlight,
              onPin: onPin,
            ),
          ),
        ],
      );
    } else {
      bubbleContent = body;
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isUser ? 10 : 12,
        ),
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width * (isUser ? 0.78 : 0.92),
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: bubbleContent,
      ),
    );
  }
}

/// Pin affordance on an agent bubble: a spinner while a pin flow runs, a filled
/// pin once saved, an outlined pin otherwise (proposal 046).
class _PinButton extends StatelessWidget {
  const _PinButton({
    required this.eventId,
    required this.pinned,
    required this.inFlight,
    required this.onPin,
  });

  final String? eventId;
  final bool pinned;
  final bool inFlight;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (inFlight) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      key: eventId != null ? Key('pin-button-$eventId') : null,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      tooltip: pinned ? 'Pinned' : 'Pin this message',
      color: pinned ? cs.primary : cs.onSurfaceVariant,
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      onPressed: pinned ? null : onPin,
    );
  }
}

/// User's confirmed pin name from [_PinConfirmDialog].
class _PinConfirmation {
  const _PinConfirmation({required this.name});
  final String name;
}

/// Confirm dialog seeded from the backend suggestion. Edits the name only;
/// the pin body is the verbatim message, copied server-side (proposal 046).
class _PinConfirmDialog extends StatefulWidget {
  const _PinConfirmDialog({required this.suggestion});

  final PinSuggestion suggestion;

  @override
  State<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<_PinConfirmDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.suggestion.name);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_PinConfirmation(name: name));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('pin-confirm-dialog'),
      title: const Text('Pin this message'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('pin-name-field'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'What to call this reference',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('pin-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('pin-confirm-button'),
          onPressed:
              _nameController.text.trim().isEmpty ? null : _submit,
          child: const Text('Pin'),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({this.toolProgress});

  final String? toolProgress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('thread-typing-indicator'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          toolProgress ?? 'Thinking\u2026',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _ModelBackendPicker extends StatelessWidget {
  const _ModelBackendPicker({
    required this.models,
    required this.backends,
    required this.selectedModel,
    required this.selectedBackend,
    required this.onSelectModel,
    required this.onSelectBackend,
  });

  final List<ModelInfo> models;
  final List<BackendInfo> backends;
  final String? selectedModel;
  final String? selectedBackend;
  final void Function(String?) onSelectModel;
  final void Function(String?) onSelectBackend;

  @override
  Widget build(BuildContext context) {
    if (backends.isEmpty) return const SizedBox.shrink();
    final currentBackend = backends.firstWhere(
      (b) => b.id == selectedBackend,
      orElse: () => backends.first,
    );
    return TextButton(
      key: const Key('thread-model-picker'),
      onPressed: () => _showPicker(context),
      child: Text(currentBackend.name),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _ModelPickerSheet(
        models: models,
        backends: backends,
        selectedModel: selectedModel,
        selectedBackend: selectedBackend,
        onSelectModel: onSelectModel,
        onSelectBackend: onSelectBackend,
      ),
    );
  }
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.models,
    required this.backends,
    required this.selectedModel,
    required this.selectedBackend,
    required this.onSelectModel,
    required this.onSelectBackend,
  });

  final List<ModelInfo> models;
  final List<BackendInfo> backends;
  final String? selectedModel;
  final String? selectedBackend;
  final void Function(String?) onSelectModel;
  final void Function(String?) onSelectBackend;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Backend',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            RadioGroup<String>(
              groupValue: widget.selectedBackend,
              onChanged: (v) {
                if (v == null) return;
                final backend =
                    widget.backends.firstWhere((b) => b.id == v);
                if (!backend.available) return;
                widget.onSelectBackend(v);
                Navigator.of(context).pop();
              },
              child: Column(
                children: widget.backends
                    .map(
                      (b) => ListTile(
                        key: Key('backend-option-${b.id}'),
                        enabled: b.available,
                        title: Text(b.name),
                        subtitle:
                            b.available ? null : const Text('Unavailable'),
                        leading: Radio<String>(value: b.id),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (widget.models.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Model',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<String>(
                  key: const Key('model-dropdown'),
                  isExpanded: true,
                  value: widget.selectedModel,
                  hint: const Text('Default model'),
                  items: widget.models
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    widget.onSelectModel(v);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.isStreaming,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool canSend;
  final bool isStreaming;
  final void Function(String text) onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('thread-input-field'),
                controller: controller,
                enabled: canSend,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Message\u2026',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: canSend ? (t) => onSend(t.trim()) : null,
              ),
            ),
            const SizedBox(width: 8),
            if (isStreaming)
              IconButton(
                key: const Key('thread-cancel-button'),
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: onCancel,
              )
            else
              IconButton(
                key: const Key('thread-send-button'),
                icon: const Icon(Icons.send),
                onPressed: canSend
                    ? () {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        onSend(text);
                      }
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
