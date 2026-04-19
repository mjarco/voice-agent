import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';

class ConversationsNotifier extends StateNotifier<ChatListState> {
  ConversationsNotifier(this._repository) : super(const ChatListLoading()) {
    load();
  }

  final ChatRepository _repository;

  Future<void> load() async {
    state = const ChatListLoading();
    try {
      final conversations = await _repository.listConversations();
      final sorted = _sort(conversations);
      state = ChatListLoaded(sorted);
    } catch (e) {
      state = ChatListError(e.toString());
    }
  }

  Future<void> refresh() => load();

  List<Conversation> _sort(List<Conversation> conversations) {
    final withActivity = conversations
        .where((c) => c.lastEventAt != null)
        .toList()
      ..sort((a, b) => b.lastEventAt!.compareTo(a.lastEventAt!));
    final withoutActivity = conversations
        .where((c) => c.lastEventAt == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...withActivity, ...withoutActivity];
  }
}
