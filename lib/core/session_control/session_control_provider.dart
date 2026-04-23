import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_dispatcher.dart';
import 'package:voice_agent/core/session_control/session_id_coordinator.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';

/// Provides a singleton [SessionIdCoordinator].
final sessionIdCoordinatorProvider = Provider<SessionIdCoordinator>((ref) {
  return SessionIdCoordinator();
});

/// Provides a [HandsFreeControlPort] implementation.
///
/// Throws by default -- must be overridden in `main.dart` (T3) to
/// delegate to [HandsFreeController].
final handsFreeControlPortProvider = Provider<HandsFreeControlPort>((ref) {
  throw UnimplementedError(
    'handsFreeControlPortProvider must be overridden in ProviderScope',
  );
});

/// Provides a [Toaster] instance.
///
/// Throws by default -- must be overridden in `main.dart` (T3) to
/// pass the app-level [GlobalKey<ScaffoldMessengerState>].
final toasterProvider = Provider<Toaster>((ref) {
  throw UnimplementedError(
    'toasterProvider must be overridden in ProviderScope',
  );
});

/// Provides a [HapticService] instance.
final hapticServiceProvider = Provider<HapticService>((ref) {
  return HapticService();
});

/// Provides a singleton [SessionControlDispatcher] wired to all
/// required dependencies.
final sessionControlDispatcherProvider =
    Provider<SessionControlDispatcher>((ref) {
  return SessionControlDispatcher(
    ttsService: ref.watch(ttsServiceProvider),
    handsFreeControlPort: ref.watch(handsFreeControlPortProvider),
    sessionIdCoordinator: ref.watch(sessionIdCoordinatorProvider),
    toaster: ref.watch(toasterProvider),
    hapticService: ref.watch(hapticServiceProvider),
  );
});
