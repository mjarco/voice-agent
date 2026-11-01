import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/location_log/data/location_log_channel.dart';
import 'package:voice_agent/features/location_log/domain/location_log_port.dart';
import 'package:voice_agent/features/location_log/domain/location_log_state.dart';

final locationLogPortProvider = Provider<LocationLogPort>((ref) {
  return LocationLogChannel();
});

/// The log exists on Android only; iOS is outside this stage.
final locationLogAvailableProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
);

final locationLogStateProvider = FutureProvider.autoDispose<LocationLogState>((
  ref,
) {
  return ref.watch(locationLogPortProvider).getState();
});
