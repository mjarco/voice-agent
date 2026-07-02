import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';

class ThreadNotifier extends StateNotifier<ThreadState> {
  ThreadNotifier({
    required String conversationId,
    required ChatRepository repository,
    required PinWriter pinWriter,
  })  : _conversationId = conversationId,
        _repository = repository,
        _pinWriter = pinWriter,
        super(const ThreadLoading()) {
    load();
  }

  final String _conversationId;
  final ChatRepository _repository;
  final PinWriter _pinWriter;

  // Session-local pin view state (proposal 046). Held as notifier fields, not on
  // the immutable Thread* states, so they survive a streaming->loaded transition
  // without threading through every state rebuild. Not reconciled with the
  // backend on reload — the pinboard is the source of truth.
  final Set<String> _pinnedEventIds = {};
  final Set<String> _pinInFlight = {};

  StreamSubscription<SseEvent>? _subscription;
  String? _currentIdempotencyKey;
  String? _activeSessionId;
  String? _currentConversationId;
  ThreadState? _preSendState;
  String? _pendingModel;
  String? _pendingBackend;

  Future<void> load() async {
    state = const ThreadLoading();
    try {
      if (_conversationId == 'new') {
        await _loadNew();
      } else {
        await _loadExisting();
      }
    } catch (e) {
      state = ThreadError(e.toString(), null);
    }
  }

  Future<void> _loadNew() async {
    final sessionId = const Uuid().v4();
    final results = await Future.wait([
      _repository.getModels(),
      _repository.getBackends(),
    ]);
    final models = results[0] as List<ModelInfo>;
    final backendOptions = results[1] as BackendOptions;
    state = ThreadEmpty(
      sessionId: sessionId,
      models: models,
      backends: backendOptions.backends,
      selectedModel: _pendingModel,
      selectedBackend: _pendingBackend ?? backendOptions.defaultBackend,
    );
    _pendingModel = null;
    _pendingBackend = null;
  }

  Future<void> _loadExisting() async {
    final results = await Future.wait([
      _repository.getConversation(_conversationId),
      _repository.getEvents(_conversationId),
      _repository.getRecords(_conversationId),
      _repository.getModels(),
      _repository.getBackends(),
    ]);
    final conversation = results[0] as Conversation?;
    if (conversation == null) {
      state = const ThreadError('Conversation not found', null);
      return;
    }
    final events = results[1] as List<ConversationEvent>;
    final records = results[2] as List<ConversationRecord>;
    final models = results[3] as List<ModelInfo>;
    final backendOptions = results[4] as BackendOptions;
    state = ThreadLoaded(
      conversation: conversation,
      events: events,
      records: records,
      models: models,
      backends: backendOptions.backends,
      selectedModel: _pendingModel,
      selectedBackend: _pendingBackend ?? backendOptions.defaultBackend,
    );
    _pendingModel = null;
    _pendingBackend = null;
  }

  Future<void> send(String content) async {
    if (state is ThreadStreaming) return;

    final currentState = state;

    switch (currentState) {
      case ThreadLoaded(
          conversation: final conv,
          events: final events,
          records: final records,
          models: final models,
          backends: final backends,
          selectedModel: final selectedModel,
          selectedBackend: final selectedBackend,
        ):
        if (conv.status == ConversationStatus.closed) return;
        _preSendState = currentState;
        final idempotencyKey = const Uuid().v4();
        _currentIdempotencyKey = idempotencyKey;
        _activeSessionId = conv.sessionId;
        state = ThreadStreaming(
          conversation: conv,
          events: events,
          records: records,
          models: models,
          backends: backends,
          selectedModel: selectedModel,
          selectedBackend: selectedBackend,
          pendingUserMessage: content,
        );
        _subscribe(
          sessionId: conv.sessionId,
          content: content,
          idempotencyKey: idempotencyKey,
          model: selectedModel,
          backend: selectedBackend,
        );

      case ThreadEmpty(
          sessionId: final sid,
          models: final models,
          backends: final backends,
          selectedModel: final selectedModel,
          selectedBackend: final selectedBackend,
        ):
        _preSendState = currentState;
        final idempotencyKey = const Uuid().v4();
        _currentIdempotencyKey = idempotencyKey;
        _activeSessionId = sid;
        state = ThreadStreaming(
          conversation: null,
          events: const [],
          records: const [],
          models: models,
          backends: backends,
          selectedModel: selectedModel,
          selectedBackend: selectedBackend,
          pendingUserMessage: content,
        );
        _subscribe(
          sessionId: sid,
          content: content,
          idempotencyKey: idempotencyKey,
          model: selectedModel,
          backend: selectedBackend,
        );

      default:
        return;
    }
  }

  void _subscribe({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  }) {
    _subscription = _repository
        .streamChat(
          sessionId: sessionId,
          content: content,
          idempotencyKey: idempotencyKey,
          model: model,
          backend: backend,
        )
        .listen(
          _onSseEvent,
          onError: _onStreamError,
          cancelOnError: true,
        );
  }

  void _onSseEvent(SseEvent event) {
    final currentStreaming = state;
    if (currentStreaming is! ThreadStreaming) return;

    switch (event.event) {
      case 'tool_use':
        final json = jsonDecode(event.data) as Map<String, dynamic>;
        final tool = json['tool'] as String? ?? '';
        state = ThreadStreaming(
          conversation: currentStreaming.conversation,
          events: currentStreaming.events,
          records: currentStreaming.records,
          models: currentStreaming.models,
          backends: currentStreaming.backends,
          selectedModel: currentStreaming.selectedModel,
          selectedBackend: currentStreaming.selectedBackend,
          pendingUserMessage: currentStreaming.pendingUserMessage,
          toolProgress: 'Using $tool\u2026',
        );

      case 'result':
        final json = jsonDecode(event.data) as Map<String, dynamic>;
        final result = ChatResult.fromMap(json);
        _currentConversationId = result.conversationId;
        _fetchAfterResult(currentStreaming);

      case 'error':
        final json = jsonDecode(event.data) as Map<String, dynamic>;
        final message = json['error'] as String? ?? 'Stream error';
        state = ThreadError(message, _preSendState);
        _preSendState = null;
    }
  }

  void _onStreamError(Object error) {
    state = ThreadError(_streamErrorMessage(error), _preSendState);
    _preSendState = null;
  }

  Future<void> _fetchAfterResult(ThreadStreaming streamingState) async {
    final convId = _currentConversationId!;
    try {
      final results = await Future.wait([
        _repository.getEvents(convId),
        _repository.getRecords(convId),
        _repository.getConversation(convId),
      ]);
      final events = results[0] as List<ConversationEvent>;
      final records = results[1] as List<ConversationRecord>;
      final conversation = results[2] as Conversation?;
      state = ThreadLoaded(
        conversation: conversation ??
            streamingState.conversation ??
            Conversation(
              conversationId: convId,
              sessionId: _activeSessionId ?? '',
              status: ConversationStatus.open,
              createdAt: DateTime.now(),
              eventCount: events.length,
            ),
        events: events,
        records: records,
        models: streamingState.models,
        backends: streamingState.backends,
        selectedModel: streamingState.selectedModel,
        selectedBackend: streamingState.selectedBackend,
      );
      _preSendState = null;
      _currentConversationId = null;
    } catch (e) {
      state = ThreadError('Failed to load messages', streamingState);
    }
  }

  String _streamErrorMessage(Object error) {
    return switch (error) {
      ApiNotConfigured() => 'API not configured',
      ApiPermanentFailure(message: final m) => m,
      ApiTransientFailure(reason: final r) => r,
      _ => error.toString(),
    };
  }

  void cancelStream() {
    if (state is! ThreadStreaming || _activeSessionId == null) return;
    _subscription?.cancel();
    _subscription = null;
    final sessionId = _activeSessionId!;
    final idempotencyKey = _currentIdempotencyKey!;
    state = _preSendState ?? const ThreadLoading();
    _preSendState = null;
    _repository
        .cancelChat(sessionId: sessionId, idempotencyKey: idempotencyKey)
        .catchError((_) {});
  }

  void selectModel(String? model) {
    final current = state;
    switch (current) {
      case ThreadLoaded():
        state = ThreadLoaded(
          conversation: current.conversation,
          events: current.events,
          records: current.records,
          models: current.models,
          backends: current.backends,
          selectedModel: model,
          selectedBackend: current.selectedBackend,
        );
      case ThreadEmpty():
        state = ThreadEmpty(
          sessionId: current.sessionId,
          models: current.models,
          backends: current.backends,
          selectedModel: model,
          selectedBackend: current.selectedBackend,
        );
      case ThreadStreaming():
        state = ThreadStreaming(
          conversation: current.conversation,
          events: current.events,
          records: current.records,
          models: current.models,
          backends: current.backends,
          selectedModel: model,
          selectedBackend: current.selectedBackend,
          pendingUserMessage: current.pendingUserMessage,
          toolProgress: current.toolProgress,
        );
      case ThreadLoading():
        _pendingModel = model;
      case ThreadError():
        break;
    }
  }

  void selectBackend(String? backend) {
    final current = state;
    switch (current) {
      case ThreadLoaded():
        state = ThreadLoaded(
          conversation: current.conversation,
          events: current.events,
          records: current.records,
          models: current.models,
          backends: current.backends,
          selectedModel: current.selectedModel,
          selectedBackend: backend,
        );
      case ThreadEmpty():
        state = ThreadEmpty(
          sessionId: current.sessionId,
          models: current.models,
          backends: current.backends,
          selectedModel: current.selectedModel,
          selectedBackend: backend,
        );
      case ThreadStreaming():
        state = ThreadStreaming(
          conversation: current.conversation,
          events: current.events,
          records: current.records,
          models: current.models,
          backends: current.backends,
          selectedModel: current.selectedModel,
          selectedBackend: backend,
          pendingUserMessage: current.pendingUserMessage,
          toolProgress: current.toolProgress,
        );
      case ThreadLoading():
        _pendingBackend = backend;
      case ThreadError():
        break;
    }
  }

  Future<void> toggleEndorse(String recordId) async {
    final current = state;
    final List<ConversationRecord> records;
    switch (current) {
      case ThreadLoaded(records: final r):
        records = r;
      case ThreadStreaming(records: final r):
        records = r;
      default:
        return;
    }

    final endorsed = await _repository.toggleEndorse(recordId);
    final updated = records.map((r) {
      if (r.recordId != recordId) return r;
      return ConversationRecord(
        recordId: r.recordId,
        conversationId: r.conversationId,
        recordType: r.recordType,
        subjectRef: r.subjectRef,
        payload: r.payload,
        confidence: r.confidence,
        originRole: r.originRole,
        assertionMode: r.assertionMode,
        userEndorsed: endorsed,
        sourceEventRefs: r.sourceEventRefs,
      );
    }).toList();

    final refreshed = state;
    switch (refreshed) {
      case ThreadLoaded():
        state = ThreadLoaded(
          conversation: refreshed.conversation,
          events: refreshed.events,
          records: updated,
          models: refreshed.models,
          backends: refreshed.backends,
          selectedModel: refreshed.selectedModel,
          selectedBackend: refreshed.selectedBackend,
        );
      case ThreadStreaming():
        state = ThreadStreaming(
          conversation: refreshed.conversation,
          events: refreshed.events,
          records: updated,
          models: refreshed.models,
          backends: refreshed.backends,
          selectedModel: refreshed.selectedModel,
          selectedBackend: refreshed.selectedBackend,
          pendingUserMessage: refreshed.pendingUserMessage,
          toolProgress: refreshed.toolProgress,
        );
      default:
        break;
    }
  }

  /// Whether [eventId] has been pinned this session (filled icon).
  bool isPinned(String eventId) => _pinnedEventIds.contains(eventId);

  /// Whether a pin flow for [eventId] is in progress (spinner + single-flight).
  bool isPinInFlight(String eventId) => _pinInFlight.contains(eventId);

  /// Starts a pin flow for a message: marks it in-flight (single-flight, drives
  /// the spinner) while fetching a suggested name + topic. Returns null when a
  /// flow is already running for this event or it is already pinned (the tap is
  /// a no-op). Rethrows on failure for the screen to surface. The in-flight mark
  /// spans only the suggest call — the confirm dialog runs behind a modal
  /// barrier, so re-taps can't happen while it is open. The create step is
  /// [confirmPin]; cancel with [cancelPin].
  Future<PinSuggestion?> beginPin(
    String conversationId,
    String eventId,
  ) async {
    if (_pinInFlight.contains(eventId) || _pinnedEventIds.contains(eventId)) {
      return null;
    }
    _pinInFlight.add(eventId);
    _touch();
    try {
      return await _pinWriter.suggestPin(conversationId, eventId);
    } finally {
      _pinInFlight.remove(eventId);
      _touch();
    }
  }

  /// Creates the pin after the user confirms. On success marks the event pinned;
  /// always clears the in-flight mark. Rethrows on failure for the screen.
  Future<PinCreateResult> confirmPin(
    String conversationId,
    String eventId, {
    required String name,
    String? topicLabel,
  }) async {
    try {
      final result = await _pinWriter.createPin(PinCreateRequest(
        conversationId: conversationId,
        eventId: eventId,
        name: name,
        topicLabel: topicLabel,
      ));
      _pinnedEventIds.add(eventId);
      return result;
    } finally {
      _pinInFlight.remove(eventId);
      _touch();
    }
  }

  /// Abandons an in-flight pin flow (dialog cancelled).
  void cancelPin(String eventId) {
    if (_pinInFlight.remove(eventId)) _touch();
  }

  /// Re-emits the current state as a fresh instance so listeners rebuild after a
  /// pin-set change (the sets are notifier fields, not state fields).
  void _touch() {
    final current = state;
    switch (current) {
      case ThreadLoaded():
        state = ThreadLoaded(
          conversation: current.conversation,
          events: current.events,
          records: current.records,
          models: current.models,
          backends: current.backends,
          selectedModel: current.selectedModel,
          selectedBackend: current.selectedBackend,
        );
      case ThreadStreaming():
        state = ThreadStreaming(
          conversation: current.conversation,
          events: current.events,
          records: current.records,
          models: current.models,
          backends: current.backends,
          selectedModel: current.selectedModel,
          selectedBackend: current.selectedBackend,
          pendingUserMessage: current.pendingUserMessage,
          toolProgress: current.toolProgress,
        );
      default:
        break;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
