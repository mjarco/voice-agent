import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/router.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';
import 'package:voice_agent/features/chat/presentation/conversations_screen.dart';
import 'package:voice_agent/features/chat/presentation/thread_screen.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';
import 'package:voice_agent/core/models/pin.dart';

/// Regression test for the pin -> source-conversation navigation.
///
/// The pin detail screen lives on a top-level route OUTSIDE the StatefulShell;
/// the chat thread (`/chat/:id`) lives INSIDE it. Pushing the in-shell route
/// from outside builds the shell at the chat branch's default location (the
/// conversations list), dropping the `:id` — the user lands on the list with no
/// selected conversation. The fix routes the pin to the standalone
/// `/conversation/:id` route, which renders ThreadScreen directly.
///
/// This drives the REAL `createRouter()` (not a hand-rolled flat router) so it
/// exercises the actual shell structure that the bug depended on.
class _StubPinsRepository implements PinsRepository {
  @override
  Future<List<PinSummary>> fetchPins(PinView view) async => [];

  @override
  Future<PinDetail> fetchPin(String recordId) async => PinDetail(
        recordId: recordId,
        pinName: 'garage pinout',
        text: '# Pinout',
        conversationId: 'conv-1',
        createdAt: DateTime.utc(2026, 6, 15),
      );

  @override
  Future<void> unpin(String recordId) async {}
}

class _StubChatRepository implements ChatRepository {
  @override
  Future<Conversation?> getConversation(String conversationId) async =>
      Conversation(
        conversationId: conversationId,
        sessionId: 'sess-1',
        status: ConversationStatus.open,
        createdAt: DateTime.utc(2026, 6, 15),
        eventCount: 0,
      );

  @override
  Future<List<ConversationEvent>> getEvents(String conversationId) async => [];

  @override
  Future<List<ConversationRecord>> getRecords(String conversationId) async =>
      [];

  @override
  Future<List<ModelInfo>> getModels({String? backend}) async => [];

  @override
  Future<BackendOptions> getBackends() async =>
      const BackendOptions(backends: []);

  @override
  Future<List<Conversation>> listConversations() async => [];

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
  Future<bool> toggleEndorse(String recordId) async => false;
}

void main() {
  testWidgets(
    'opening a pin\'s source conversation lands on the thread, not the list',
    (tester) async {
      // Start the real router directly on the pin detail route so the test
      // mirrors a user who navigated Pins -> a pin, then taps "open".
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pinsRepositoryProvider.overrideWithValue(_StubPinsRepository()),
            chatRepositoryProvider.overrideWithValue(_StubChatRepository()),
          ],
          child: MaterialApp.router(
            routerConfig: createRouter(initialLocation: '/pins/abc'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The open-conversation action is present (pin has a conversation_id).
      final action = find.byKey(const Key('pin-detail-open-conversation'));
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      // We must land on the specific thread, NOT the conversations list.
      expect(find.byType(ThreadScreen), findsOneWidget);
      expect(find.byType(ConversationsScreen), findsNothing);
    },
  );
}
