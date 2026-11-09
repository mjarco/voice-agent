import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/links/link_opener.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/widgets/agent_markdown_style.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';

/// Full verbatim view of a single saved reference (proposal 045).
/// Renders the markdown body with `flutter_markdown_plus` in the chat's style;
/// links open in the browser, tables scroll sideways, images fit the width.
///
/// An edit used to give the pin a new `record_id` (ADR-CORE-111 of
/// personal-agent); since pins have their own table it keeps its id
/// (ADR-CORE-117). The screen keeps the current id itself and shows what the
/// save answered either way.
class PinDetailScreen extends ConsumerStatefulWidget {
  const PinDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  ConsumerState<PinDetailScreen> createState() => _PinDetailScreenState();
}

class _PinDetailScreenState extends ConsumerState<PinDetailScreen> {
  late String _recordId = widget.recordId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinDetailNotifierProvider(_recordId));
    final notifier = ref.read(pinDetailNotifierProvider(_recordId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(state is PinDetailLoaded ? state.pin.pinName : 'Pin'),
        actions: [
          if (state is PinDetailLoaded) ...[
            if (_conversationId(state.pin) case final conversationId?)
              IconButton(
                key: const Key('pin-detail-open-conversation'),
                icon: const Icon(Icons.forum_outlined),
                tooltip: 'Open conversation',
                onPressed: () => context.push('/conversation/$conversationId'),
              ),
            IconButton(
              key: const Key('pin-detail-copy'),
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () => _copy(state.pin.text),
            ),
            IconButton(
              key: const Key('pin-detail-edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => _edit(state.pin),
            ),
            IconButton(
              key: const Key('pin-detail-unpin'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Unpin',
              onPressed: _confirmUnpin,
            ),
          ],
        ],
      ),
      body: switch (state) {
        PinDetailLoading() =>
          const Center(child: CircularProgressIndicator()),
        PinDetailLoaded(pin: final pin) => _Body(pin: pin),
        PinDetailError(message: final message) =>
          _ErrorState(message: message, onRetry: notifier.refresh),
      },
    );
  }

  /// The source conversation id, or null when absent/empty (legacy pins) so
  /// the "open conversation" action only shows when there is a thread to open.
  String? _conversationId(PinDetail pin) {
    final id = pin.conversationId;
    return (id == null || id.isEmpty) ? null : id;
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  /// A form closed without a write may have been refused because the pin has a
  /// newer version, so what this screen shows is read again.
  Future<void> _edit(PinDetail pin) async {
    final saved = await context.push<PinDetail>(
      '/pins/${pin.recordId}/edit',
      extra: pin,
    );
    if (!mounted) return;
    if (saved != null) {
      setState(() => _recordId = saved.recordId);
      ref.read(pinDetailNotifierProvider(_recordId).notifier).show(saved);
      return;
    }
    await ref.read(pinDetailNotifierProvider(_recordId).notifier).refresh();
    _leaveIfGone();
  }

  /// An earlier version answers 404 for good (ADR-CORE-111), so only the list,
  /// which reloads on return, can lead to the pin now.
  void _leaveIfGone() {
    if (!mounted) return;
    final state = ref.read(pinDetailNotifierProvider(_recordId));
    if (state is PinDetailError && state.gone) context.pop();
  }

  Future<void> _confirmUnpin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('pin-detail-unpin-dialog'),
        title: const Text('Unpin reference?'),
        content: const Text('This removes it from your pins.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('pin-detail-unpin-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final notifier = ref.read(pinDetailNotifierProvider(_recordId).notifier);
    final ok = await notifier.unpin();
    if (!mounted) return;
    if (ok) {
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.lastActionError ?? 'Unpin failed')),
      );
      _leaveIfGone();
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.pin});

  final PinDetail pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A table keeps its columns' widths and scrolls sideways, as code does.
    final style = agentMarkdownStyle(Theme.of(context)).copyWith(
      tableColumnWidth: const IntrinsicColumnWidth(),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        key: const Key('pin-detail-markdown'),
        data: pin.text,
        selectable: true,
        softLineBreak: true,
        styleSheet: style,
        onTapLink: (text, href, title) => _openLink(context, ref, href),
        imageBuilder: (uri, title, alt) => _PinImage(uri: uri, alt: alt),
      ),
    );
  }

  Future<void> _openLink(
    BuildContext context,
    WidgetRef ref,
    String? href,
  ) async {
    final uri = href == null ? null : Uri.tryParse(href);
    final opened =
        uri != null && await ref.read(linkOpenerProvider).open(uri);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Cannot open the link: ${href ?? ''}')),
      );
  }
}

/// An image of a pin, loaded from the web and fitted to the width. One that
/// fails, or is not on the web, shows its description instead.
class _PinImage extends StatelessWidget {
  const _PinImage({required this.uri, required this.alt});

  final Uri uri;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final fallback = _ImageFallback(alt: alt);
    if (uri.scheme != 'http' && uri.scheme != 'https') return fallback;
    return Image.network(
      uri.toString(),
      key: const Key('pin-detail-image'),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (alt == null || alt!.trim().isEmpty) ? 'Image' : alt!.trim();
    return Row(
      key: const Key('pin-detail-image-fallback'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('pin-detail-retry-button'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
