import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:voice_agent/core/media_button/media_button_port.dart';

/// Platform-channel implementation of [MediaButtonPort].
///
/// Uses a [MethodChannel] for activate/deactivate commands and an
/// [EventChannel] for receiving media button events from the native
/// layer. Channel names follow ADR-PLATFORM-005.
class MediaButtonService implements MediaButtonPort {
  MediaButtonService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('com.voiceagent/media_button'),
        _eventChannel = eventChannel ??
            const EventChannel('com.voiceagent/media_button/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Stream<MediaButtonEvent> get events {
    return _eventChannel
        .receiveBroadcastStream()
        .map<MediaButtonEvent?>((dynamic event) {
          debugPrint('[MediaButtonDbg] raw event from native: $event');
          if (event == 'togglePlayPause') {
            return MediaButtonEvent.togglePlayPause;
          }
          developer.log(
            'Unknown media button event: $event',
            name: 'MediaButtonService',
          );
          return null;
        })
        .where((e) => e != null)
        .cast<MediaButtonEvent>();
  }

  @override
  Future<void> activate() async {
    debugPrint('[MediaButtonDbg] Dart→native activate() invoked');
    try {
      await _methodChannel.invokeMethod<void>('activate');
      debugPrint('[MediaButtonDbg] Dart→native activate() returned');
    } catch (e) {
      developer.log(
        'Failed to activate media button: $e',
        name: 'MediaButtonService',
      );
    }
  }

  @override
  Future<void> deactivate() async {
    debugPrint('[MediaButtonDbg] Dart→native deactivate() invoked');
    try {
      await _methodChannel.invokeMethod<void>('deactivate');
    } catch (e) {
      developer.log(
        'Failed to deactivate media button: $e',
        name: 'MediaButtonService',
      );
    }
  }
}
