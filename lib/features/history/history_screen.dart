import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/features/history/history_notifier.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(historyListProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: state.items.isEmpty && !state.isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No transcripts yet'),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: state.items.length + (state.isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final item = state.items[index];
                return _HistoryListTile(
                  item: item,
                  onTap: () => _showDetail(item),
                );
              },
            ),
    );
  }

  void _showDetail(TranscriptWithStatus item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TranscriptDetailScreen(
          item: item,
          onCopy: () => _copyText(item.text),
          onResend: item.status == DisplaySyncStatus.failed
              ? () => _resend(item.id)
              : null,
          onDelete: () => _delete(item.id),
        ),
      ),
    );
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  void _resend(String id) {
    ref.read(historyListProvider.notifier).resendItem(id);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queued for resend')),
    );
  }

  void _delete(String id) {
    Navigator.of(context).pop();
    ref.read(historyListProvider.notifier).deleteItem(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transcript deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Undo would require re-inserting — for MVP, refresh from DB
            ref.read(historyListProvider.notifier).refresh();
          },
        ),
      ),
    );
  }
}

class _HistoryListTile extends StatelessWidget {
  const _HistoryListTile({
    required this.item,
    required this.onTap,
  });

  final TranscriptWithStatus item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        item.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          _StatusDot(status: item.status),
          const SizedBox(width: 4),
          Text(_statusLabel(item.status)),
          const Spacer(),
          Text(
            _formatTime(item.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _statusLabel(DisplaySyncStatus status) {
    return switch (status) {
      DisplaySyncStatus.sent => 'Sent',
      DisplaySyncStatus.pending => 'Pending',
      DisplaySyncStatus.failed => 'Failed',
    };
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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

class _TranscriptDetailScreen extends StatelessWidget {
  const _TranscriptDetailScreen({
    required this.item,
    required this.onCopy,
    this.onResend,
    required this.onDelete,
  });

  final TranscriptWithStatus item;
  final VoidCallback onCopy;
  final VoidCallback? onResend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                        switch (item.status) {
                          DisplaySyncStatus.sent => 'Sent',
                          DisplaySyncStatus.pending => 'Pending',
                          DisplaySyncStatus.failed => 'Failed',
                        },
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
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  if (onResend != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onResend,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Resend'),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
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
                                onDelete();
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
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
}
