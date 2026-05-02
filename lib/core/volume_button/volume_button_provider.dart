import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/volume_button/volume_button_port.dart';
import 'package:voice_agent/core/volume_button/volume_button_service.dart';

/// Provides a [VolumeButtonPort] backed by platform channels.
final volumeButtonProvider = Provider<VolumeButtonPort>((ref) {
  return VolumeButtonService();
});
