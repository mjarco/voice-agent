import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';
import 'package:voice_agent/features/chat/presentation/thread_screen.dart';

// ---------------------------------------------------------------------------
// Stub repository
// ---------------------------------------------------------------------------

class _StubRepository implements ChatRepository {
  Conversation? conversationResult;
  List<ConversationEvent> eventsResult = [];
  List<ConversationRecord> recordsResult = [];
  BackendOptions backendsResult = const BackendOptions(backends: [
    BackendInfo(id: 'b1', name: 'Claude', available: true),
  ]);
  bool toggleResult = true;

  StreamController<SseEvent>? streamController;

  @override
  Future<List<Conversation>> listConversations() async => [];

  @override
  Future<Conversation?> getConversation(String conversationId) async =>
      conversationResult;

  @override
  Future<List<ConversationEvent>> getEvents(String conversationId) async =>
      eventsResult;

  @override
  Future<List<ConversationRecord>> getRecords(String conversationId) async =>
      recordsResult;

  @override
  Future<List<ModelInfo>> getModels({String? backend}) async => [];

  @override
  Future<BackendOptions> getBackends() async => backendsResult;

  @override
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  }) {
    streamController = StreamController<SseEvent>();
    return streamController!.stream;
  }

  @override
  Future<void> cancelChat({
    required String sessionId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<bool> toggleEndorse(String recordId) async => toggleResult;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Conversation _conv({
  String id = 'conv-1',
  String sessionId = 'sess-1',
  ConversationStatus status = ConversationStatus.open,
  String? preview,
}) {
  return Conversation(
    conversationId: id,
    sessionId: sessionId,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    eventCount: 0,
    firstMessagePreview: preview,
  );
}

ConversationEvent _event({String id = 'evt-1', EventRole role = EventRole.user, String content = 'Hello'}) {
  return ConversationEvent(
    eventId: id,
    conversationId: 'conv-1',
    sequence: 1,
    role: role,
    content: content,
    receivedAt: DateTime(2026, 1, 1),
  );
}

ConversationRecord _record({String id = 'rec-1', bool endorsed = false, String subjectRef = 'A decision'}) {
  return ConversationRecord(
    recordId: id,
    conversationId: 'conv-1',
    recordType: RecordType.decision,
    subjectRef: subjectRef,
    payload: const {},
    confidence: 0.9,
    originRole: OriginRole.agent,
    assertionMode: 'assert',
    userEndorsed: endorsed,
    sourceEventRefs: const [],
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _StubRepository repository,
  String conversationId = 'conv-1',
}) async {
  final router = GoRouter(
    initialLocation: '/chat/$conversationId',
    routes: [
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) =>
            ThreadScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('Settings')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ThreadScreen', () {
    testWidgets('shows loading indicator before data resolves', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      final router = GoRouter(
        initialLocation: '/chat/conv-1',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) =>
                ThreadScreen(conversationId: state.pathParameters['id']!),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // First pump — still in loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders user message bubble', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(role: EventRole.user, content: 'User says hi')];
      await _pumpScreen(tester, repository: repo);

      expect(find.text('User says hi'), findsOneWidget);
    });

    testWidgets('renders agent message bubble', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'a1', role: EventRole.agent, content: 'Agent replies')];
      await _pumpScreen(tester, repository: repo);

      expect(find.text('Agent replies'), findsOneWidget);
    });

    testWidgets('shows record badges after last agent bubble', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'a1', role: EventRole.agent, content: 'Reply')]
        ..recordsResult = [_record(subjectRef: 'Decision badge')];
      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('thread-record-badges')), findsOneWidget);
      expect(find.text('Decision badge'), findsOneWidget);
    });

    testWidgets('record badge shows empty star when not endorsed', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'a1', role: EventRole.agent)]
        ..recordsResult = [_record(id: 'rec-1', endorsed: false)];
      await _pumpScreen(tester, repository: repo);

      final starIcon = find.byKey(const Key('badge-star-rec-1'));
      expect(starIcon, findsOneWidget);
      final icon = tester.widget<Icon>(starIcon);
      expect(icon.icon, Icons.star_border);
    });

    testWidgets('record badge shows filled star when endorsed', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'a1', role: EventRole.agent)]
        ..recordsResult = [_record(id: 'rec-2', endorsed: true)];
      await _pumpScreen(tester, repository: repo);

      final icon = tester.widget<Icon>(find.byKey(const Key('badge-star-rec-2')));
      expect(icon.icon, Icons.star);
    });

    testWidgets('tapping record badge calls toggleEndorse', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'a1', role: EventRole.agent)]
        ..recordsResult = [_record(id: 'rec-tap')];
      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.byKey(const Key('badge-rec-tap')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('badge-star-rec-tap')), findsOneWidget);
    });

    testWidgets('send button is enabled when loaded and open', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('thread-send-button')),
      );
      expect(sendButton.onPressed, isNotNull);
    });

    testWidgets('send button is disabled for closed conversation', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv(status: ConversationStatus.closed);
      await _pumpScreen(tester, repository: repo);

      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('thread-send-button')),
      );
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('closed conversation shows closed label', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv(status: ConversationStatus.closed);
      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('thread-closed-label')), findsOneWidget);
    });

    testWidgets('tapping send button calls notifier.send', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      await tester.enterText(find.byKey(const Key('thread-input-field')), 'test message');
      await tester.tap(find.byKey(const Key('thread-send-button')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('thread-cancel-button')), findsOneWidget);
    });

    testWidgets('input field is cleared after send', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      await tester.enterText(find.byKey(const Key('thread-input-field')), 'hello');
      await tester.tap(find.byKey(const Key('thread-send-button')));
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(const Key('thread-input-field')));
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('shows pending user message during streaming', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      await tester.enterText(find.byKey(const Key('thread-input-field')), 'pending msg');
      await tester.tap(find.byKey(const Key('thread-send-button')));
      await tester.pump();

      expect(find.byKey(const Key('thread-pending-message')), findsOneWidget);
      expect(find.text('pending msg'), findsOneWidget);
    });

    testWidgets('shows typing indicator during streaming', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      await tester.enterText(find.byKey(const Key('thread-input-field')), 'hello');
      await tester.tap(find.byKey(const Key('thread-send-button')));
      await tester.pump();

      expect(find.byKey(const Key('thread-typing-indicator')), findsOneWidget);
    });

    testWidgets('settings icon navigates to settings', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.byKey(const Key('thread-settings-icon')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('model picker button opens bottom sheet', (tester) async {
      final repo = _StubRepository()..conversationResult = _conv();
      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.byKey(const Key('thread-model-picker')));
      await tester.pumpAndSettle();

      expect(find.text('Backend'), findsOneWidget);
      expect(find.byKey(const Key('backend-option-b1')), findsOneWidget);
    });

    testWidgets('new conversation shows New Chat title', (tester) async {
      final repo = _StubRepository();
      await _pumpScreen(tester, repository: repo, conversationId: 'new');

      expect(find.text('New Chat'), findsOneWidget);
    });
  });
}
