import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:voice_agent/core/volume_button/volume_button_port.dart';

/// Platform-channel implementation of [VolumeButtonPort].
class VolumeButtonService implements VolumeButtonPort {
  VolumeButtonService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('com.voiceagent/volume_button'),
        _eventChannel = eventChannel ??
            const EventChannel('com.voiceagent/volume_button/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Stream<VolumeButtonEvent> get events {
    return _eventChannel
        .receiveBroadcastStream()
        .map<VolumeButtonEvent?>((dynamic event) {
          debugPrint('[VolumeBtnDbg] raw event from native: $event');
          if (event == 'up') return VolumeButtonEvent.up;
          if (event == 'down') return VolumeButtonEvent.down;
          developer.log(
            'Unknown volume button event: $event',
            name: 'VolumeButtonService',
          );
          return null;
        })
        .where((e) => e != null)
        .cast<VolumeButtonEvent>();
  }

  @override
  Future<void> activate() async {
    debugPrint('[VolumeBtnDbg] Dart→native activate() invoked');
    try {
      await _methodChannel.invokeMethod<void>('activate');
      debugPrint('[VolumeBtnDbg] Dart→native activate() returned');
    } catch (e) {
      developer.log(
        'Failed to activate volume button: $e',
        name: 'VolumeButtonService',
      );
    }
  }

  @override
  Future<void> deactivate() async {
    debugPrint('[VolumeBtnDbg] Dart→native deactivate() invoked');
    try {
      await _methodChannel.invokeMethod<void>('deactivate');
    } catch (e) {
      developer.log(
        'Failed to deactivate volume button: $e',
        name: 'VolumeButtonService',
      );
    }
  }
}
