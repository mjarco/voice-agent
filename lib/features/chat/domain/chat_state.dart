import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';

sealed class ChatListState {
  const ChatListState();
}

class ChatListLoading extends ChatListState {
  const ChatListLoading();
}

class ChatListLoaded extends ChatListState {
  const ChatListLoaded(this.conversations);
  final List<Conversation> conversations;
}

class ChatListError extends ChatListState {
  const ChatListError(this.message);
  final String message;
}

sealed class ThreadState {
  const ThreadState();
}

class ThreadLoading extends ThreadState {
  const ThreadLoading();
}

class ThreadEmpty extends ThreadState {
  const ThreadEmpty({
    required this.sessionId,
    required this.models,
    required this.backends,
    this.selectedModel,
    this.selectedBackend,
  });

  final String sessionId;
  final List<ModelInfo> models;
  final List<BackendInfo> backends;
  final String? selectedModel;
  final String? selectedBackend;
}

class ThreadLoaded extends ThreadState {
  const ThreadLoaded({
    required this.conversation,
    required this.events,
    required this.records,
    required this.models,
    required this.backends,
    this.selectedModel,
    this.selectedBackend,
  });

  final Conversation conversation;
  final List<ConversationEvent> events;
  final List<ConversationRecord> records;
  final List<ModelInfo> models;
  final List<BackendInfo> backends;
  final String? selectedModel;
  final String? selectedBackend;
}

class ThreadStreaming extends ThreadState {
  const ThreadStreaming({
    this.conversation,
    required this.events,
    required this.records,
    required this.models,
    required this.backends,
    this.selectedModel,
    this.selectedBackend,
    required this.pendingUserMessage,
    this.toolProgress,
  });

  final Conversation? conversation;
  final List<ConversationEvent> events;
  final List<ConversationRecord> records;
  final List<ModelInfo> models;
  final List<BackendInfo> backends;
  final String? selectedModel;
  final String? selectedBackend;
  final String pendingUserMessage;
  final String? toolProgress;
}

class ThreadError extends ThreadState {
  const ThreadError(this.message, this.previousState);
  final String message;
  final ThreadState? previousState;
}
