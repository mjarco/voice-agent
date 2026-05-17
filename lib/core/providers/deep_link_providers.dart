import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cold-start deep-link payload — populated in `app_main.dart` before
/// `runApp` from `getNotificationAppLaunchDetails()`, consumed exactly once
/// on first frame by `App.build()`'s `addPostFrameCallback`, then set to
/// null.
///
/// Per ADR-PLATFORM-008 — two-channel cross-app-entry deep link with
/// one-shot + stream invariant. Placement in `core/providers/` per
/// ADR-ARCH-008 (ephemeral cross-feature state).
///
/// Default: null. Overridden in `app_main.dart` with the cold-start payload
/// when the app was launched by tapping a notification.
final pendingDeepLinkProvider = StateProvider<String?>((ref) => null);

/// Warm-path notification tap stream — registered AFTER the cold-start read
/// returns, so a cold-start payload is never observed on this channel.
///
/// Per ADR-PLATFORM-008. In production overridden in `app_main.dart` to
/// expose `LocalNotificationService.tapStream`. Default for tests is an
/// empty stream.
final notificationTapStreamProvider = StreamProvider<String>((ref) {
  return const Stream<String>.empty();
});
