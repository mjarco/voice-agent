import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/audio_focus/audio_focus_port.dart';
import 'package:voice_agent/core/audio_focus/audio_focus_service.dart';

/// The app's own audio focus: the platform channel on Android, none
/// elsewhere (ADR-AUDIO-014).
final audioFocusProvider = Provider<AudioFocusPort>((ref) {
  return Platform.isAndroid ? AudioFocusService() : const NoAudioFocus();
});
