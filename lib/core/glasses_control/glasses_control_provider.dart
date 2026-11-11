import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/glasses_control/glasses_control_port.dart';
import 'package:voice_agent/core/glasses_control/glasses_control_service.dart';

/// glass-native runs on Android only (ADR-AUDIO-016).
final glassesControlProvider = Provider<GlassesControlPort>((ref) {
  return Platform.isAndroid
      ? GlassesControlService()
      : const NoGlassesControl();
});
