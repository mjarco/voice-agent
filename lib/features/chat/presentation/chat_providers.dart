import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/chat/data/api_chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';
import 'package:voice_agent/features/chat/presentation/conversations_notifier.dart';
import 'package:voice_agent/features/chat/presentation/thread_notifier.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ApiChatRepository(
    apiClient: ref.watch(apiClientProvider),
    sseClient: ref.watch(sseClientProvider),
  );
});

final conversationsNotifierProvider =
    StateNotifierProvider<ConversationsNotifier, ChatListState>((ref) {
  return ConversationsNotifier(ref.watch(chatRepositoryProvider));
});

final threadNotifierProvider =
    StateNotifierProvider.family<ThreadNotifier, ThreadState, String>(
  (ref, conversationId) => ThreadNotifier(
    conversationId: conversationId,
    repository: ref.watch(chatRepositoryProvider),
  ),
);
