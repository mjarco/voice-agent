import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/features/places/presentation/places_providers.dart';

/// Sends what waits while the app is in use, as transcripts are (ADR-NET-002):
/// at the start, on coming back, and when the link returns. A place saved with
/// no link waits for one of those. A failure here must never reach the rest of
/// the app.
final placesSyncProvider = Provider<void>((ref) {
  void sendWaiting() {
    final notifier = ref.read(placesNotifierProvider.notifier);
    if (ref.read(placesNotifierProvider).pendingCount > 0) {
      unawaited(notifier.sync());
    }
  }

  final lifecycle = AppLifecycleListener(onResume: sendWaiting);
  final links = ConnectivityService().statusStream.listen((status) {
    if (status == ConnectivityStatus.online) sendWaiting();
  }, onError: (Object _) {});
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(links.cancel());
  });

  () async {
    await ref.read(appConfigProvider.notifier).loadCompleted;
    await ref.read(placesNotifierProvider.notifier).sync();
  }();
});
