import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
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
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
    Map<String, dynamic>? subject,
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
      GoRoute(
        path: '/matters',
        builder: (_, _) =>const Scaffold(body: Text('Matters')),
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

    testWidgets('renders the floating add and the app menu',
        (tester) async {
      await _pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byType(FloatingActionButton),
          matching: find.byIcon(Icons.add),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.add)),
        findsNothing,
      );
      expect(find.byKey(const Key('app-pins')), findsOneWidget);
      expect(find.byKey(const Key('app-settings')), findsOneWidget);
      expect(find.byKey(const Key('app-places')), findsOneWidget);
    });

    testWidgets('every button has a label a screen reader can read',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpScreen(tester);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('has no matters icon: Sprawy are a tab (ADR-ARCH-012)',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('conversations-matters-icon')), findsNothing);
    });

    testWidgets('the floating add navigates to /chat/new', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('conversations-new')));
      await tester.pumpAndSettle();

      expect(find.text('Thread new'), findsOneWidget);
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

      expect(find.textContaining('Hello there'), findsOneWidget);
      expect(find.textContaining('Second chat'), findsOneWidget);
    });

    testWidgets('conversation tile shows event count as subtitle',
        (tester) async {
      final repo = _StubRepository(
        conversations: [_conv(preview: 'Test', eventCount: 7)],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.textContaining('7 messages'), findsOneWidget);
    });

    testWidgets('each conversation is its own card (va-polish)',
        (tester) async {
      final repo = _StubRepository(
        conversations: [
          _conv(id: 'conv-1', preview: 'Hello there'),
          _conv(id: 'conv-2', preview: 'Second chat'),
        ],
      );

      await _pumpScreen(tester, repository: repo);

      for (final text in ['Hello there', 'Second chat']) {
        expect(
          find.ancestor(of: find.textContaining(text), matching: find.byType(Card)),
          findsOneWidget,
        );
      }
    });

    test('conversationTimeLabel: hour today, day before, year before', () {
      final now = DateTime(2026, 11, 11, 15, 0);
      expect(conversationTimeLabel(DateTime(2026, 11, 11, 9, 5), now), '09:05');
      expect(conversationTimeLabel(DateTime(2026, 11, 3, 9, 5), now), '03.11');
      expect(
        conversationTimeLabel(DateTime(2025, 12, 30, 9, 5), now),
        '30.12.2025',
      );
    });

    testWidgets('a row shows its matter first and how it was held (07 §2)',
        (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(conversations: [
        Conversation.fromMap({
          'conversation_id': 'c-1', 'session_id': 's-1', 'status': 'open',
          'created_at': '2026-11-15T10:00:00Z', 'event_count': 3,
          'first_message_preview': 'wycena płytek',
          'subject': 'matter', 'matter': {'id': 'm-1', 'title': 'Remont łazienki'}, 'channel': 'voice',
        }),
        Conversation.fromMap({
          'conversation_id': 'c-2', 'session_id': 's-2', 'status': 'open',
          'created_at': '2026-11-15T09:00:00Z', 'event_count': 2,
          'first_message_preview': 'co mam jutro', 'channel': 'typed',
        }),
        Conversation.fromMap({
          'conversation_id': 'c-3', 'session_id': 's-3', 'status': 'open',
          'created_at': '2026-11-15T08:00:00Z', 'event_count': 2,
          'first_message_preview': 'wypiłem kawę', 'subject': 'diet', 'channel': 'voice',
        }),
      ]));

      final matter = find.byKey(const Key('conversation-c-1'));
      expect(find.descendant(of: matter, matching: find.text('Remont łazienki')), findsOneWidget);
      expect(find.descendant(of: matter, matching: find.byIcon(Icons.mic_none)), findsOneWidget);
      final day = find.byKey(const Key('conversation-c-2'));
      expect(find.descendant(of: day, matching: find.text('Bez sprawy')), findsOneWidget);
      expect(find.descendant(of: day, matching: find.byIcon(Icons.keyboard_outlined)), findsOneWidget);
      // ADR-NET-009: held on the diet.
      expect(find.descendant(of: find.byKey(const Key('conversation-c-3')), matching: find.text('Jedzenie')),
          findsOneWidget);
    });

    testWidgets('conversation tile shows fallback preview when null',
        (tester) async {
      final repo = _StubRepository(
        conversations: [_conv(preview: null)],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.textContaining('New conversation'), findsOneWidget);
    });

    testWidgets('tapping a conversation navigates to thread', (tester) async {
      final repo = _StubRepository(
        conversations: [_conv(id: 'conv-42', preview: 'Go to thread')],
      );

      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.textContaining('Go to thread'));
      await tester.pumpAndSettle();

      expect(find.text('Thread conv-42'), findsOneWidget);
    });

    testWidgets('the Settings icon opens settings', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('app-settings')));
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
