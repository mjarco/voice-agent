import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/features/history/history_notifier.dart';

class TranscriptDetailScreen extends ConsumerWidget {
  const TranscriptDetailScreen({super.key, required this.transcriptId});

  final String transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Find the item from the history list state
    final historyState = ref.watch(historyListProvider);
    final item = historyState.items
        .where((i) => i.id == transcriptId)
        .firstOrNull;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transcript')),
        body: const Center(child: Text('Transcript not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transcript')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusDot(status: item.status),
                      const SizedBox(width: 8),
                      Text(
                        _statusLabel(item.status),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    item.text,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copyText(context, item.text),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  if (item.status == DisplaySyncStatus.failed) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _resend(context, ref, item.id),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Resend'),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _confirmDelete(context, ref, item.id),
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(DisplaySyncStatus status) {
    return switch (status) {
      DisplaySyncStatus.sent => 'Sent',
      DisplaySyncStatus.pending => 'Pending',
      DisplaySyncStatus.failed => 'Failed',
    };
  }

  void _copyText(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  void _resend(BuildContext context, WidgetRef ref, String id) {
    ref.read(historyListProvider.notifier).resendItem(id);
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queued for resend')),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String id) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transcript?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyListProvider.notifier).deleteItem(id);
              context.pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Transcript deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final DisplaySyncStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DisplaySyncStatus.sent => Colors.green,
      DisplaySyncStatus.pending => Colors.orange,
      DisplaySyncStatus.failed => Colors.red,
    };

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
