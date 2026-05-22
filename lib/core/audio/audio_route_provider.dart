import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/audio_route_service.dart';
import 'package:voice_agent/core/audio/platform_audio_route_service.dart';

/// Provides the app-wide [AudioRouteService] (P042).
final audioRouteServiceProvider = Provider<AudioRouteService>((ref) {
  return PlatformAudioRouteService();
});
