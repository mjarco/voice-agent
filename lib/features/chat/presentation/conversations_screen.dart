import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
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
        actions: [
          IconButton(
            key: const Key('conversations-new-icon'),
            icon: const Icon(Icons.add),
            onPressed: () async {
              ref.invalidate(threadNotifierProvider('new'));
              await context.push('/chat/new');
              notifier.refresh();
            },
          ),
          IconButton(
            key: const Key('conversations-settings-icon'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
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
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      return _ConversationTile(
                        conversation: conversations[index],
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
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview =
        conversation.firstMessagePreview ?? 'New conversation';
    final subtitle = '${conversation.eventCount} messages';

    return ListTile(
      title: Text(preview),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
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
