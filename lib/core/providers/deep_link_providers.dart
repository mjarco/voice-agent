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
/// Per ADR-PLATFORM-008. In production overridden in `app_main.dart` with one
/// single-subscription stream of the plugin's taps and the arrival alerts'
/// (ADR-NOTIF-003): App is its only listener, and it must not be invalidated,
/// or the stream would be listened to twice. Default for tests is an empty
/// stream.
final notificationTapStreamProvider = StreamProvider<String>((ref) {
  return const Stream<String>.empty();
});

/// The `extra` of a `go` made by a notification tap. A new one per tap, so a
/// tap to the location already shown is still a new navigation, and a screen
/// can tell it from a rebuild (ADR-NOTIF-003: a second arrival tap re-selects
/// the place's store types).
class DeepLinkTap {}

/// One share from another app. No `==`, so the same text shared twice still
/// reaches a listener.
class SharedText {
  SharedText(this.text);

  final String text;
}

/// Cold-start shared text: read in `app_main.dart` before `runApp`, consumed
/// once on first frame, then set to null (ADR-PLATFORM-008).
final pendingSharedTextProvider = StateProvider<String?>((ref) => null);

/// Text shared while the app runs (ADR-PLATFORM-008). In production overridden
/// in `app_main.dart`; the default for tests is an empty stream.
final sharedTextStreamProvider = StreamProvider<SharedText>((ref) {
  return const Stream<SharedText>.empty();
});
