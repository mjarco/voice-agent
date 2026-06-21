import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';

/// Full verbatim view of a single saved reference (proposal 045).
/// Renders the markdown body with `flutter_markdown_plus`, mirroring how the
/// Chat thread screen renders agent messages.
class PinDetailScreen extends ConsumerWidget {
  const PinDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pinDetailNotifierProvider(recordId));
    final notifier = ref.read(pinDetailNotifierProvider(recordId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(state is PinDetailLoaded ? state.pin.pinName : 'Pin'),
        actions: [
          if (state is PinDetailLoaded) ...[
            IconButton(
              key: const Key('pin-detail-copy'),
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () => _copy(context, state.pin.text),
            ),
            IconButton(
              key: const Key('pin-detail-unpin'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Unpin',
              onPressed: () => _confirmUnpin(context, ref),
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

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _confirmUnpin(BuildContext context, WidgetRef ref) async {
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

    final notifier = ref.read(pinDetailNotifierProvider(recordId).notifier);
    final ok = await notifier.unpin();
    if (!context.mounted) return;
    if (ok) {
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.lastActionError ?? 'Unpin failed')),
      );
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.pin});

  final PinDetail pin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        key: const Key('pin-detail-markdown'),
        data: pin.text,
        selectable: true,
        softLineBreak: true,
      ),
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
