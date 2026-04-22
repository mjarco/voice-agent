import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a hands-free session is active (Listening / Capturing /
/// Stopping / WithBacklog). Written by `HandsFreeController` at three
/// lifecycle boundaries (`startSession`, `stopSession`,
/// `_terminateWithError`); read by `SyncWorker` (P027) and any future
/// consumer that needs to gate on an active session.
///
/// Mirrors the `appForegroundedProvider` pattern (core-layer
/// `StateProvider<bool>` written by a feature) to avoid a cross-feature
/// import from `features/api_sync` → `features/recording`. See ADR-NET-002
/// (amended in P027) and ADR-PLATFORM-006 (amended in P027).
final sessionActiveProvider = StateProvider<bool>((ref) => false);
