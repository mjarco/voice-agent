/// Holds the current client-local conversation ID.
///
/// The ID is purely client-side -- used for diagnostics and log
/// correlation. The outbound request body is unchanged (no
/// `conversation_id` field per canonical P049 section 5).
class SessionIdCoordinator {
  String? _currentConversationId;

  /// The current conversation ID, or null when a fresh conversation
  /// will be opened on the next send.
  String? get currentConversationId => _currentConversationId;

  /// Clears the local conversation ID so the next outbound request
  /// allows the backend to open a fresh conversation.
  Future<void> resetSession() async {
    _currentConversationId = null;
  }

  /// Adopts a conversation ID returned by the backend after a
  /// successful reply so subsequent sends keep the same local tag.
  void adoptConversationId(String id) {
    _currentConversationId = id;
  }
}
