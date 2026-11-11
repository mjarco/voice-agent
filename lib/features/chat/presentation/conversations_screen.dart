import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/widgets/app_bar_actions.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationsNotifierProvider);
    final notifier = ref.read(conversationsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: const [AppBarActions()],
      ),
      // A new conversation from a floating "+", as in Sprawy.
      floatingActionButton: FloatingActionButton(
        key: const Key('conversations-new'),
        tooltip: 'New conversation',
        onPressed: () async {
          ref.invalidate(threadNotifierProvider('new'));
          await context.push('/chat/new');
          notifier.refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: switch (state) {
        ChatListLoading() =>
          const Center(child: CircularProgressIndicator()),
        ChatListLoaded(conversations: final conversations) =>
          conversations.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  onRefresh: notifier.refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      return _ConversationTile(
                        conversation: conversations[index],
                        now: DateTime.now(),
                        onTap: () async {
                          await context
                              .push('/chat/${conversations[index].conversationId}');
                          notifier.refresh();
                        },
                      );
                    },
                  ),
                ),
        ChatListError(message: final message) =>
          _ErrorState(message: message, onRetry: notifier.refresh),
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.now,
    required this.onTap,
  });

  final Conversation conversation;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview =
        conversation.firstMessagePreview ?? 'New conversation';
    final subtitle = '${conversation.eventCount} messages';
    final at = (conversation.lastEventAt ?? conversation.createdAt).toLocal();

    // A card per conversation, as in Sprawy, so the rows read apart.
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitle),
        trailing: Text(
          conversationTimeLabel(at, now),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// The hour for today, the day and month for this year, the full date before.
String conversationTimeLabel(DateTime at, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (at.year == now.year && at.month == now.month && at.day == now.day) {
    return '${two(at.hour)}:${two(at.minute)}';
  }
  if (at.year == now.year) return '${two(at.day)}.${two(at.month)}';
  return '${two(at.day)}.${two(at.month)}.${at.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No conversations yet'),
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
          Text(message),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
