/// Cross-feature signal for hands-free session lifecycle.
///
/// **Producer:** `HandsFreeController` in `features/recording/`.
/// **Consumer:** `ActivationController` in `features/activation/`.
sealed class HandsFreeSessionStatus {
  const HandsFreeSessionStatus();
}

class HandsFreeSessionInactive extends HandsFreeSessionStatus {
  const HandsFreeSessionInactive();
}

class HandsFreeSessionRunning extends HandsFreeSessionStatus {
  const HandsFreeSessionRunning();
}

class HandsFreeSessionCompletedOk extends HandsFreeSessionStatus {
  const HandsFreeSessionCompletedOk();
}

class HandsFreeSessionFailed extends HandsFreeSessionStatus {
  const HandsFreeSessionFailed({required this.message});
  final String message;
}
