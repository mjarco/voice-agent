import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';
import 'package:voice_agent/features/chat/presentation/conversations_screen.dart';

class _StubRepository implements ChatRepository {
  final List<Conversation> conversations;
  final bool shouldFail;

  const _StubRepository({this.conversations = const [], this.shouldFail = false});

  @override
  Future<List<Conversation>> listConversations() async {
    if (shouldFail) throw Exception('network error');
    return conversations;
  }

  @override
  Future<List<ConversationEvent>> getEvents(String conversationId) async => [];

  @override
  Future<List<ConversationRecord>> getRecords(String conversationId) async => [];

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
  String? preview,
  int eventCount = 3,
}) {
  return Conversation(
    conversationId: id,
    sessionId: 'sess-$id',
    status: ConversationStatus.open,
    createdAt: DateTime(2026, 1, 1),
    eventCount: eventCount,
    firstMessagePreview: preview,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  ChatRepository? repository,
}) async {
  final repo = repository ?? const _StubRepository();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>const ConversationsScreen(),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Thread ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) =>const Scaffold(body: Text('Settings')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ConversationsScreen', () {
    testWidgets('shows loading indicator before data resolves', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(const _StubRepository()),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) =>const ConversationsScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      // First pump — state is ChatListLoading before microtasks run
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders AppBar with Chat title', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Chat'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders add and settings icons', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.byKey(const Key('conversations-new-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('conversations-settings-icon')),
        findsOneWidget,
      );
    });

    testWidgets('shows empty state when no conversations', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('No conversations yet'), findsOneWidget);
    });

    testWidgets('shows conversation tiles when loaded', (tester) async {
      final repo = _StubRepository(
        conversations: [
          _conv(id: 'conv-1', preview: 'Hello there'),
          _conv(id: 'conv-2', preview: 'Second chat'),
        ],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('Second chat'), findsOneWidget);
    });

    testWidgets('conversation tile shows event count as subtitle',
        (tester) async {
      final repo = _StubRepository(
        conversations: [_conv(preview: 'Test', eventCount: 7)],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('7 messages'), findsOneWidget);
    });

    testWidgets('conversation tile shows fallback preview when null',
        (tester) async {
      final repo = _StubRepository(
        conversations: [_conv(preview: null)],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('New conversation'), findsOneWidget);
    });

    testWidgets('tapping a conversation navigates to thread', (tester) async {
      final repo = _StubRepository(
        conversations: [_conv(id: 'conv-42', preview: 'Go to thread')],
      );

      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.text('Go to thread'));
      await tester.pumpAndSettle();

      expect(find.text('Thread conv-42'), findsOneWidget);
    });

    testWidgets('settings icon navigates to settings', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('conversations-settings-icon')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows error message on failure', (tester) async {
      await _pumpScreen(
        tester,
        repository: const _StubRepository(shouldFail: true),
      );

      expect(find.text('Exception: network error'), findsOneWidget);
    });

    testWidgets('error state shows retry button', (tester) async {
      await _pumpScreen(
        tester,
        repository: const _StubRepository(shouldFail: true),
      );

      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
