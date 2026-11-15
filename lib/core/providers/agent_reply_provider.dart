import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/agent_action.dart';

/// Latest text reply from the personal-agent backend.
///
/// **Producer:** `SyncWorker` via `sync_provider.dart` — set on `ApiSuccess`
/// with a `message` field in the response body.
///
/// **Consumer:** `RecordingScreen` — displays the reply in a dismissible card.
final latestAgentReplyProvider = StateProvider<String?>((ref) => null);

/// What the latest reply did (personal-agent ADR-API-127, C10): set with each
/// spoken reply, [] when it did nothing with a card. The conversation field of
/// a screen that knows a kind shows its card under the reply (ADR-NET-009).
final latestAgentActionsProvider = StateProvider<List<AgentAction>>((ref) => const []);
