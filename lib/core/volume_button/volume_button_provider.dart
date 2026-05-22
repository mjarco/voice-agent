import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/audio/audio_route_provider.dart';
import 'package:voice_agent/core/volume_button/volume_button_port.dart';
import 'package:voice_agent/core/volume_button/volume_button_service.dart';

/// Provides a [VolumeButtonPort] backed by platform channels.
///
/// P042: wired to [audioRouteServiceProvider] so route-change `outputVolume`
/// artefacts are filtered out of the volume-button event stream.
final volumeButtonProvider = Provider<VolumeButtonPort>((ref) {
  return VolumeButtonService(
    audioRouteService: ref.watch(audioRouteServiceProvider),
  );
});
