import 'dart:developer' as developer;

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
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event == 'togglePlayPause') {
        return MediaButtonEvent.togglePlayPause;
      }
      developer.log(
        'Unknown media button event: $event',
        name: 'MediaButtonService',
      );
      return MediaButtonEvent.togglePlayPause;
    });
  }

  @override
  Future<void> activate() async {
    try {
      await _methodChannel.invokeMethod<void>('activate');
    } catch (e) {
      developer.log(
        'Failed to activate media button: $e',
        name: 'MediaButtonService',
      );
    }
  }

  @override
  Future<void> deactivate() async {
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
