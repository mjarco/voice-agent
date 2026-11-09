import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';
import 'package:voice_agent/features/chat/presentation/thread_screen.dart';

import '../../../core/network/fake_shopping_proposals.dart';

// ---------------------------------------------------------------------------
// Stub repository
// ---------------------------------------------------------------------------

class _StubRepository implements ChatRepository {
  Conversation? conversationResult;
  List<ConversationEvent> eventsResult = [];
  BackendOptions backendsResult = const BackendOptions(backends: [
    BackendInfo(id: 'b1', name: 'Claude', available: true),
  ]);

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

class _FakePinWriter implements PinWriter {
  @override
  Future<PinSuggestion> suggestPinFromText(String text) async =>
      throw UnimplementedError();

  @override
  Future<PinCreateResult> createTextPin(PinTextCreateRequest request) async =>
      throw UnimplementedError();

  @override
  Future<PinCreateResult> editPin(
    String recordId, {
    String? name,
    String? text,
  }) async =>
      throw UnimplementedError();

  PinSuggestion suggestResult =
      const PinSuggestion(name: 'ESP32 pinout');
  Object? suggestError;
  Object? createError;
  final List<PinCreateRequest> created = [];

  @override
  Future<PinSuggestion> suggestPin(
    String conversationId,
    String eventId,
  ) async {
    if (suggestError != null) throw suggestError!;
    return suggestResult;
  }

  @override
  Future<PinCreateResult> createPin(PinCreateRequest request) async {
    created.add(request);
    if (createError != null) throw createError!;
    return PinCreateResult(
      pin: PinDetail(
        recordId: 'pin-1',
        pinName: request.name,
        text: 'body',
        createdAt: DateTime(2026, 1, 1),
      ),
      created: true,
    );
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _StubRepository repository,
  String conversationId = 'conv-1',
  _FakePinWriter? pinWriter,
  FakeShoppingProposals? proposals,
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
      GoRoute(
        path: '/pins',
        builder: (_, _) => const Scaffold(body: Text('Pins screen')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        pinWriterProvider.overrideWithValue(pinWriter ?? _FakePinWriter()),
        shoppingProposalsPortProvider
            .overrideWithValue(proposals ?? FakeShoppingProposals()),
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
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            pinWriterProvider.overrideWithValue(_FakePinWriter()),
            shoppingProposalsPortProvider
                .overrideWithValue(FakeShoppingProposals()),
          ],
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

      expect(find.text('Agent replies', findRichText: true), findsOneWidget);
    });

    testWidgets('agent bubble renders markdown (asterisks stripped)',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [
          _event(id: 'a1', role: EventRole.agent, content: '**bold word**'),
        ];
      await _pumpScreen(tester, repository: repo);

      // Markdown processed: rendered text omits the asterisks.
      expect(find.text('bold word', findRichText: true), findsOneWidget);
      expect(find.text('**bold word**', findRichText: true), findsNothing);
    });

    testWidgets('agent bubble strips SSML lang wrappers', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [
          _event(
            id: 'a1',
            role: EventRole.agent,
            content: 'Use the <lang xml:lang="en-US">API</lang> endpoint',
          ),
        ];
      await _pumpScreen(tester, repository: repo);

      expect(
        find.text('Use the API endpoint', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a reply carries no knowledge row (personal-agent R2)',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'a1', role: EventRole.agent, content: 'Reply')];
      await _pumpScreen(tester, repository: repo);

      expect(find.text('Reply'), findsOneWidget);
      expect(find.textContaining('knowledge item'), findsNothing);
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

  group('pin a message (P046)', () {
    _StubRepository agentRepo() => _StubRepository()
      ..conversationResult = _conv()
      ..eventsResult = [
        _event(id: 'evt-agent', role: EventRole.agent, content: 'Agent reply'),
      ];

    testWidgets('agent bubble shows a pin button, user bubble does not',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [
          _event(id: 'evt-user', role: EventRole.user, content: 'Hi'),
          _event(id: 'evt-agent', role: EventRole.agent, content: 'Reply'),
        ];
      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('pin-button-evt-agent')), findsOneWidget);
      expect(find.byKey(const Key('pin-button-evt-user')), findsNothing);
    });

    testWidgets('no pin button when the event has no server conversation id',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [
          ConversationEvent(
            eventId: 'evt-agent',
            conversationId: '',
            sequence: 1,
            role: EventRole.agent,
            content: 'Reply',
            receivedAt: DateTime(2026, 1, 1),
          ),
        ];
      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('pin-button-evt-agent')), findsNothing);
    });

    testWidgets('tapping the pin button opens a dialog seeded from suggestion',
        (tester) async {
      final pin = _FakePinWriter()
        ..suggestResult =
            const PinSuggestion(name: 'Garage pinout');
      await _pumpScreen(tester, repository: agentRepo(), pinWriter: pin);

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pin-confirm-dialog')), findsOneWidget);
      expect(find.text('Garage pinout'), findsOneWidget);
      // A pin has no topic since personal-agent R2: the dialog asks the name only.
      expect(find.byKey(const Key('pin-topic-field')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('pin-confirm-dialog')),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
    });

    testWidgets('confirming creates the pin with the exact payload',
        (tester) async {
      final pin = _FakePinWriter()
        ..suggestResult =
            const PinSuggestion(name: 'Garage pinout');
      await _pumpScreen(tester, repository: agentRepo(), pinWriter: pin);

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-confirm-button')));
      await tester.pumpAndSettle();

      final req = pin.created.single;
      expect(req.conversationId, 'conv-1');
      expect(req.eventId, 'evt-agent');
      expect(req.name, 'Garage pinout');
      expect(req.toMap().keys, {'conversation_id', 'event_id', 'name'});
      expect(find.text('Pinned as "Garage pinout"'), findsOneWidget);
    });

    testWidgets('the pin button becomes filled after a successful pin',
        (tester) async {
      await _pumpScreen(tester, repository: agentRepo());

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-confirm-button')));
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('pin-button-evt-agent')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.push_pin);
    });

    testWidgets('the Open snackbar action navigates to the pinboard',
        (tester) async {
      await _pumpScreen(tester, repository: agentRepo());

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-confirm-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Pins screen'), findsOneWidget);
    });

    testWidgets('cancelling the dialog pins nothing', (tester) async {
      final pin = _FakePinWriter();
      await _pumpScreen(tester, repository: agentRepo(), pinWriter: pin);

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-cancel-button')));
      await tester.pumpAndSettle();

      expect(pin.created, isEmpty);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('pin-button-evt-agent')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.push_pin_outlined);
    });

    testWidgets('a suggest failure shows a snackbar and opens no dialog',
        (tester) async {
      final pin = _FakePinWriter()..suggestError = Exception('offline');
      await _pumpScreen(tester, repository: agentRepo(), pinWriter: pin);

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pin-confirm-dialog')), findsNothing);
      expect(find.textContaining('Could not prepare pin'), findsOneWidget);
    });

    // A malformed answer throws a TypeError, not an Exception: the pin may be
    // saved on the server, so the screen must still say what happened.
    testWidgets('a malformed create answer still shows a snackbar',
        (tester) async {
      final pin = _FakePinWriter()
        ..createError = TypeError();
      await _pumpScreen(tester, repository: agentRepo(), pinWriter: pin);

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-confirm-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not pin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a malformed suggest answer still shows a snackbar',
        (tester) async {
      final pin = _FakePinWriter()..suggestError = TypeError();
      await _pumpScreen(tester, repository: agentRepo(), pinWriter: pin);

      await tester.tap(find.byKey(const Key('pin-button-evt-agent')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pin-confirm-dialog')), findsNothing);
      expect(find.textContaining('Could not prepare pin'), findsOneWidget);
    });
  });

  group('ThreadScreen — shopping proposals', () {
    Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

    double top(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(Key(key))).dy;

    testWidgets('a card sits under the reply to its message', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [
          _event(id: 'u1'),
          _event(id: 'a1', role: EventRole.agent),
          _event(id: 'u2'),
          _event(id: 'a2', role: EventRole.agent),
        ];
      final proposals = FakeShoppingProposals()
        ..rows = [sampleProposal(id: 'p1', userEventId: 'u1')];

      await _pumpScreen(tester, repository: repo, proposals: proposals);

      final card = top(tester, 'shopping-proposal-p1');
      expect(card, greaterThan(top(tester, 'thread-event-a1')));
      expect(card, lessThan(top(tester, 'thread-event-u2')));
    });

    testWidgets('with no reply the card sits under the message',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'u1')];
      final proposals = FakeShoppingProposals()
        ..rows = [sampleProposal(id: 'p1', userEventId: 'u1')];

      await _pumpScreen(tester, repository: repo, proposals: proposals);

      expect(
        top(tester, 'shopping-proposal-p1'),
        greaterThan(top(tester, 'thread-event-u1')),
      );
    });

    testWidgets('two cards of one message keep their order', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [
          _event(id: 'u1'),
          _event(id: 'a1', role: EventRole.agent),
        ];
      final proposals = FakeShoppingProposals()
        ..rows = [
          sampleProposal(id: 'p1', userEventId: 'u1'),
          sampleProposal(id: 'p2', userEventId: 'u1', text: 'mleko'),
        ];

      await _pumpScreen(tester, repository: repo, proposals: proposals);

      expect(
        top(tester, 'shopping-proposal-p1'),
        lessThan(top(tester, 'shopping-proposal-p2')),
      );
    });

    testWidgets('a proposal of a message not in the thread is not shown',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'u1')];
      final proposals = FakeShoppingProposals()
        ..rows = [sampleProposal(id: 'p1', userEventId: 'elsewhere')];

      await _pumpScreen(tester, repository: repo, proposals: proposals);

      expect(find.byKey(const Key('shopping-proposal-p1')), findsNothing);
    });

    testWidgets('a reopened thread shows what became of a proposal',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'u1')];
      final proposals = FakeShoppingProposals()
        ..rows = [
          sampleProposal(id: 'p1', userEventId: 'u1', state: 'accepted'),
        ];

      await _pumpScreen(tester, repository: repo, proposals: proposals);

      expect(find.text('added'), findsOneWidget);
      expect(
        find.byKey(const Key('shopping-proposal-accept-p1')),
        findsNothing,
      );
    });

    testWidgets('tapping a button answers and the card shows it',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'u1')];
      final proposals = FakeShoppingProposals()
        ..rows = [sampleProposal(id: 'p1', userEventId: 'u1')];

      await _pumpScreen(tester, repository: repo, proposals: proposals);
      await tester.tap(find.byKey(const Key('shopping-proposal-skip-p1')));
      await settle(tester);

      expect(proposals.skipped, ['p1']);
      expect(find.text('skipped'), findsOneWidget);
    });

    testWidgets('a thread opened again shows an answer given elsewhere',
        (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'u1')];
      final proposals = FakeShoppingProposals()
        ..rows = [sampleProposal(id: 'p1', userEventId: 'u1')];
      final show = ValueNotifier(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            pinWriterProvider.overrideWithValue(_FakePinWriter()),
            shoppingProposalsPortProvider.overrideWithValue(proposals),
          ],
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) => visible
                  ? const ThreadScreen(conversationId: 'conv-1')
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('skipped'), findsNothing);

      show.value = false;
      await settle(tester);
      proposals.rows = [
        sampleProposal(id: 'p1', userEventId: 'u1', state: 'skipped'),
      ];
      show.value = true;
      await settle(tester);

      expect(find.text('skipped'), findsOneWidget);
    });

    testWidgets('a failed read leaves the thread standing', (tester) async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(id: 'u1', content: 'Still here')];
      final proposals = FakeShoppingProposals()..failReads = true;

      await _pumpScreen(tester, repository: repo, proposals: proposals);

      expect(find.text('Still here'), findsOneWidget);
    });
  });
}
