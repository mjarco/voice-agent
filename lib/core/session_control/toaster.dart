import 'package:flutter/material.dart';

/// Lightweight toast abstraction wrapping [ScaffoldMessengerState] via
/// a [GlobalKey].
///
/// The key is owned by `app/app.dart` and passed to
/// `MaterialApp.scaffoldMessengerKey`. The [Toaster] is exposed through
/// `toasterProvider` so the [SessionControlDispatcher] can show toasts
/// without a `BuildContext`.
class Toaster {
  Toaster(this._messengerKey);

  final GlobalKey<ScaffoldMessengerState> _messengerKey;

  /// Shows a floating [SnackBar] with the given [message].
  void show(
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
