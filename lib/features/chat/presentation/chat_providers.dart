import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/core/providers/agent_turns_provider.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/core/providers/shopping_list_changes_provider.dart';
import 'package:voice_agent/core/subject/utterance_subject.dart';
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

/// The key of a new thread opened in [subject] (Napisz on a matter's screen
/// or the diet's).
String newThreadIn(UtteranceSubject subject) => 'new@${subject.key}';

/// The key of a new thread opened on a matter.
String newThreadOnMatter(String matterId) => newThreadIn(UtteranceSubject.matter(matterId));

/// A thread by its conversation id; `new` is a new thread, `new@<subject key>`
/// a new thread in a subject ([newThreadIn]).
final threadNotifierProvider =
    StateNotifierProvider.family<ThreadNotifier, ThreadState, String>(
  (ref, key) {
    final shoppingChanges = ref.read(shoppingListChangesProvider.notifier);
    final turns = ref.read(agentTurnsProvider.notifier);
    final inSubject = key.startsWith('new@');
    return ThreadNotifier(
      conversationId: inSubject ? 'new' : key,
      subject: inSubject ? UtteranceSubject.ofKey(key.substring(4)) : UtteranceSubject.day,
      repository: ref.watch(chatRepositoryProvider),
      pinWriter: ref.watch(pinWriterProvider),
      proposals: ref.watch(shoppingProposalsPortProvider),
      onShoppingChanged: () => shoppingChanges.state++,
      onAnswered: () => turns.state++,
    );
  },
);
