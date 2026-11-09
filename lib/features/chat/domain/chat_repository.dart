import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/network/sse_client.dart';

class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.backendId,
  });

  final String id;
  final String name;
  final String backendId;

  factory ModelInfo.fromMap(Map<String, dynamic> map) {
    return ModelInfo(
      id: map['id'] as String,
      name: map['label'] as String,
      backendId: map['backend'] as String,
    );
  }
}

class BackendInfo {
  const BackendInfo({
    required this.id,
    required this.name,
    required this.available,
  });

  final String id;
  final String name;
  final bool available;

  factory BackendInfo.fromMap(Map<String, dynamic> map) {
    return BackendInfo(
      id: map['id'] as String,
      name: map['label'] as String,
      available: map['available'] as bool,
    );
  }
}

class BackendOptions {
  const BackendOptions({required this.backends, this.defaultBackend});

  final List<BackendInfo> backends;
  final String? defaultBackend;
}

class ChatResult {
  const ChatResult({
    required this.conversationId,
    required this.userEventId,
    this.agentEventId,
    required this.reply,
    this.backend,
    this.shoppingProposals = const [],
  });

  final String conversationId;
  final String userEventId;
  final String? agentEventId;
  final String reply;
  final String? backend;

  /// What this turn proposed; absent from the frame when it proposed nothing.
  final List<ShoppingProposal> shoppingProposals;

  factory ChatResult.fromMap(Map<String, dynamic> map) {
    final proposals = map['shopping_proposals'] as List<dynamic>? ?? const [];
    return ChatResult(
      conversationId: map['conversation_id'] as String,
      userEventId: map['user_event_id'] as String,
      agentEventId: map['agent_event_id'] as String?,
      reply: map['reply'] as String,
      backend: map['backend'] as String?,
      shoppingProposals: proposals
          .map((e) => ShoppingProposal.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
    // warnings intentionally ignored in V1
  }
}

abstract class ChatRepository {
  Future<List<Conversation>> listConversations();
  Future<List<ConversationEvent>> getEvents(String conversationId);
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  });
  Future<void> cancelChat({
    required String sessionId,
    required String idempotencyKey,
  });
  Future<Conversation?> getConversation(String conversationId);
  Future<List<ModelInfo>> getModels({String? backend});
  Future<BackendOptions> getBackends();
}
