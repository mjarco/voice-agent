import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'package:voice_agent/core/audio_focus/audio_focus_port.dart';

/// Platform-channel implementation of [AudioFocusPort] (Android).
///
/// A [MethodChannel] for `request` / `abandon` and an [EventChannel] for the
/// losses. Channel names follow ADR-PLATFORM-005.
class AudioFocusService implements AudioFocusPort {
  AudioFocusService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('com.voiceagent/audio_focus'),
        _eventChannel = eventChannel ??
            const EventChannel('com.voiceagent/audio_focus/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Future<bool> request() async {
    try {
      return await _methodChannel.invokeMethod<bool>('request') ?? false;
    } on Exception catch (e) {
      // A missing handler (MissingPluginException) or a platform error
      // counts as refused, so the caller ends in Standby, not in a
      // Listening with no recorder.
      developer.log('Audio focus request failed: $e',
          name: 'AudioFocusService');
      return false;
    }
  }

  @override
  Future<void> abandon() async {
    try {
      await _methodChannel.invokeMethod<void>('abandon');
    } on Exception catch (e) {
      developer.log('Audio focus abandon failed: $e',
          name: 'AudioFocusService');
    }
  }

  @override
  Stream<AudioFocusLoss> get losses => _eventChannel
      .receiveBroadcastStream()
      .map<AudioFocusLoss?>((dynamic event) => switch (event) {
            'loss' => AudioFocusLoss.permanent,
            'lossTransient' => AudioFocusLoss.transient,
            'lossTransientCanDuck' => AudioFocusLoss.mayDuck,
            _ => null,
          })
      .where((loss) => loss != null)
      .cast<AudioFocusLoss>();
}
