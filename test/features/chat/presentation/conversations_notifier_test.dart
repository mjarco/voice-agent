import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';
import 'package:voice_agent/features/chat/presentation/conversations_notifier.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/network/sse_client.dart';

class _StubRepository implements ChatRepository {
  List<Conversation> nextResult = [];
  bool throwOnLoad = false;

  int loadCount = 0;

  @override
  Future<List<Conversation>> listConversations() async {
    loadCount++;
    if (throwOnLoad) throw Exception('load failed');
    return nextResult;
  }

  @override
  Future<List<ConversationEvent>> getEvents(String conversationId) async => [];

  @override
  Future<List<ConversationRecord>> getRecords(String conversationId) async =>
      [];

  @override
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  }) =>
      const Stream.empty();

  @override
  Future<void> cancelChat({
    required String sessionId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<Conversation?> getConversation(String conversationId) async => null;

  @override
  Future<List<ModelInfo>> getModels({String? backend}) async => [];

  @override
  Future<BackendOptions> getBackends() async =>
      const BackendOptions(backends: []);

  @override
  Future<bool> toggleEndorse(String recordId) async => false;
}

Conversation _conv({
  String id = 'conv-1',
  DateTime? lastEventAt,
  DateTime? createdAt,
}) {
  return Conversation(
    conversationId: id,
    sessionId: 'sess-$id',
    status: ConversationStatus.open,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    eventCount: 1,
    lastEventAt: lastEventAt,
  );
}

void main() {
  late _StubRepository repo;

  setUp(() {
    repo = _StubRepository();
  });

  test('initial state is loading', () {
    repo.nextResult = [];
    final notifier = ConversationsNotifier(repo);
    expect(notifier.state, isA<ChatListLoading>());
  });

  test('load() transitions to loaded with conversations', () async {
    repo.nextResult = [_conv()];
    final notifier = ConversationsNotifier(repo);
    await Future.microtask(() {});
    await Future.microtask(() {});

    expect(notifier.state, isA<ChatListLoaded>());
    final loaded = notifier.state as ChatListLoaded;
    expect(loaded.conversations, hasLength(1));
  });

  test('load() transitions to error on failure', () async {
    repo.throwOnLoad = true;
    final notifier = ConversationsNotifier(repo);
    await Future.microtask(() {});
    await Future.microtask(() {});

    expect(notifier.state, isA<ChatListError>());
    final error = notifier.state as ChatListError;
    expect(error.message, contains('load failed'));
  });

  test('sort: conversations with lastEventAt come before those without',
      () async {
    repo.nextResult = [
      _conv(id: 'no-activity'),
      _conv(id: 'with-activity', lastEventAt: DateTime(2026, 1, 5)),
    ];
    final notifier = ConversationsNotifier(repo);
    await Future.microtask(() {});
    await Future.microtask(() {});

    final loaded = notifier.state as ChatListLoaded;
    expect(loaded.conversations.first.conversationId, 'with-activity');
    expect(loaded.conversations.last.conversationId, 'no-activity');
  });

  test('sort: conversations with lastEventAt sorted descending', () async {
    repo.nextResult = [
      _conv(id: 'older', lastEventAt: DateTime(2026, 1, 1)),
      _conv(id: 'newer', lastEventAt: DateTime(2026, 1, 10)),
    ];
    final notifier = ConversationsNotifier(repo);
    await Future.microtask(() {});
    await Future.microtask(() {});

    final loaded = notifier.state as ChatListLoaded;
    expect(loaded.conversations.first.conversationId, 'newer');
    expect(loaded.conversations.last.conversationId, 'older');
  });

  test('sort: conversations without lastEventAt sorted by createdAt desc',
      () async {
    repo.nextResult = [
      _conv(id: 'older-created', createdAt: DateTime(2026, 1, 1)),
      _conv(id: 'newer-created', createdAt: DateTime(2026, 1, 10)),
    ];
    final notifier = ConversationsNotifier(repo);
    await Future.microtask(() {});
    await Future.microtask(() {});

    final loaded = notifier.state as ChatListLoaded;
    expect(loaded.conversations.first.conversationId, 'newer-created');
  });

  test('refresh() calls load() again', () async {
    repo.nextResult = [_conv()];
    final notifier = ConversationsNotifier(repo);
    await Future.microtask(() {});
    await Future.microtask(() {});

    final countBefore = repo.loadCount;
    await notifier.refresh();

    expect(repo.loadCount, greaterThan(countBefore));
  });
}
