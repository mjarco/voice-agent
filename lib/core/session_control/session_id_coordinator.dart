/// Holds the current client-local conversation ID.
///
/// The ID is purely client-side -- used for diagnostics and log
/// correlation. The outbound request body is unchanged (no
/// `conversation_id` field per canonical P049 section 5).
class SessionIdCoordinator {
  String? _currentConversationId;

  /// Listeners notified after [resetSession] runs. Used by P036's TTS
  /// reply buffer to clear itself without importing a feature module.
  final List<void Function()> _resetListeners = [];

  /// Listeners notified when [adoptConversationId] changes the current
  /// conversation tag (i.e. `newId != currentConversationId`). Used by
  /// P036's TTS reply buffer to clear when the backend rotates the
  /// conversation without an explicit `reset_session` signal.
  final List<void Function(String newId)> _conversationChangeListeners = [];

  /// The current conversation ID, or null when a fresh conversation
  /// will be opened on the next send.
  String? get currentConversationId => _currentConversationId;

  /// Clears the local conversation ID so the next outbound request
  /// allows the backend to open a fresh conversation.
  Future<void> resetSession() async {
    _currentConversationId = null;
    for (final listener in List.of(_resetListeners)) {
      listener();
    }
  }

  /// Adopts a conversation ID returned by the backend after a
  /// successful reply so subsequent sends keep the same local tag.
  ///
  /// If [id] differs from the previously-held ID, registered
  /// conversation-change listeners are fired (P036).
  void adoptConversationId(String id) {
    final changed = id != _currentConversationId;
    _currentConversationId = id;
    if (changed) {
      for (final listener in List.of(_conversationChangeListeners)) {
        listener(id);
      }
    }
  }

  /// Registers a listener for [resetSession]. Returns a disposer that
  /// removes the listener when called.
  void Function() addResetListener(void Function() listener) {
    _resetListeners.add(listener);
    return () => _resetListeners.remove(listener);
  }

  /// Registers a listener fired whenever [adoptConversationId] changes
  /// the current ID. Returns a disposer that removes the listener.
  void Function() addConversationChangeListener(
    void Function(String newId) listener,
  ) {
    _conversationChangeListeners.add(listener);
    return () => _conversationChangeListeners.remove(listener);
  }
}
