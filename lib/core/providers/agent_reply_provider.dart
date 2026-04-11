import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Latest text reply from the personal-agent backend.
///
/// **Producer:** `SyncWorker` via `sync_provider.dart` — set on `ApiSuccess`
/// with a `message` field in the response body.
///
/// **Consumer:** `RecordingScreen` — displays the reply in a dismissible card.
final latestAgentReplyProvider = StateProvider<String?>((ref) => null);
