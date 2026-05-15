import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
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
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(threadNotifierProvider(widget.conversationId));
    final notifier =
        ref.read(threadNotifierProvider(widget.conversationId).notifier);

    final String title;
    final List<ConversationEvent> events;
    final List<ConversationRecord> records;
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
        records = const [];
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
          records: final r,
          models: final m,
          backends: final b,
          selectedModel: final sm,
          selectedBackend: final sb,
        ):
        title = conv.firstMessagePreview ?? 'New Chat';
        events = e;
        records = r;
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
          records: final r,
          models: final m,
          backends: final b,
          selectedModel: final sm,
          selectedBackend: final sb,
          pendingUserMessage: final pm,
          toolProgress: final tp,
        ):
        title = conv?.firstMessagePreview ?? 'New Chat';
        events = e;
        records = r;
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
                  final widgets = <Widget>[];
                  for (var i = 0; i < reversed.length; i++) {
                    final event = reversed[i];
                    widgets.add(_MessageBubble(
                      key: Key('thread-event-${event.eventId}'),
                      content: event.content,
                      role: event.role,
                    ));
                    final isLastAgent = event.role == EventRole.agent &&
                        reversed
                            .sublist(0, i)
                            .every((e) => e.role != EventRole.agent);
                    if (isLastAgent && records.isNotEmpty) {
                      widgets.add(_RecordBadges(
                        records: records,
                        onToggleEndorse: notifier.toggleEndorse,
                      ));
                    }
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

final _ssmlLangStrip =
    RegExp(r'<lang xml:lang="[a-z]{2,3}(?:-[A-Z]{2,4})?">|</lang>');

String _stripSsmlLang(String text) => text.replaceAll(_ssmlLangStrip, '');

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.content,
    required this.role,
    this.pending = false,
  });

  final String content;
  final EventRole role;
  final bool pending;

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
        styleSheet: _agentMarkdownStyle(theme),
        softLineBreak: true,
      );
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
        child: body,
      ),
    );
  }
}

MarkdownStyleSheet _agentMarkdownStyle(ThemeData theme) {
  final tt = theme.textTheme;
  final cs = theme.colorScheme;
  final base = tt.bodyMedium?.copyWith(height: 1.45, color: cs.onSurface);
  final mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: (base?.fontSize ?? 14) - 1,
    color: cs.onSurface,
  );
  final codeBg = cs.surfaceContainerHigh;

  return MarkdownStyleSheet(
    p: base,
    pPadding: const EdgeInsets.only(bottom: 4),
    h1: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h2: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h3: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h4: tt.titleSmall,
    h5: tt.titleSmall,
    h6: tt.titleSmall,
    strong: const TextStyle(fontWeight: FontWeight.w700),
    em: const TextStyle(fontStyle: FontStyle.italic),
    code: mono.copyWith(backgroundColor: codeBg),
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: BorderRadius.circular(8),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: cs.primary, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
    blockquote: base?.copyWith(color: cs.onSurfaceVariant),
    listBullet: base,
    listIndent: 20,
    a: TextStyle(
      color: cs.primary,
      decoration: TextDecoration.underline,
    ),
    tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
    tableHead: const TextStyle(fontWeight: FontWeight.w700),
    tableCellsPadding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: cs.outlineVariant, width: 1),
      ),
    ),
  );
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

class _RecordBadges extends StatefulWidget {
  const _RecordBadges({
    required this.records,
    required this.onToggleEndorse,
  });

  final List<ConversationRecord> records;
  final void Function(String recordId) onToggleEndorse;

  @override
  State<_RecordBadges> createState() => _RecordBadgesState();
}

class _RecordBadgesState extends State<_RecordBadges> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.records.length;
    final label = '$n knowledge item${n == 1 ? '' : 's'}';

    return Padding(
      key: const Key('thread-record-badges'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('thread-knowledge-toggle'),
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: widget.records
                          .map(
                            (r) => _RecordBadge(
                              record: r,
                              onToggleEndorse: () =>
                                  widget.onToggleEndorse(r.recordId),
                            ),
                          )
                          .toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _RecordBadge extends StatelessWidget {
  const _RecordBadge({
    required this.record,
    required this.onToggleEndorse,
  });

  final ConversationRecord record;
  final VoidCallback onToggleEndorse;

  @override
  Widget build(BuildContext context) {
    final text = recordDisplayText(record);
    return GestureDetector(
      key: Key('badge-${record.recordId}'),
      onTap: onToggleEndorse,
      child: Chip(
        avatar: Icon(
          record.userEndorsed ? Icons.star : Icons.star_border,
          size: 16,
          key: Key('badge-star-${record.recordId}'),
        ),
        label: Text(text, style: const TextStyle(fontSize: 12)),
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
