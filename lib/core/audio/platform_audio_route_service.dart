import 'dart:io';

import 'package:flutter/services.dart';
import 'package:voice_agent/core/audio/audio_route_service.dart';

/// [AudioRouteService] backed by the
/// `com.voiceagent/audio_session/route_changes` EventChannel, registered
/// on iOS by `AudioSessionBridge`.
///
/// Off iOS the channel is not implemented, so the stream is empty and the
/// channel is never listened to: a listen would fail with a
/// `MissingPluginException` that Flutter logs before [Stream.handleError]
/// sees it (seen on Android at every start, #351).
class PlatformAudioRouteService implements AudioRouteService {
  PlatformAudioRouteService({EventChannel? eventChannel, bool? isIOS})
      : _eventChannel = eventChannel ??
            const EventChannel('com.voiceagent/audio_session/route_changes'),
        _isIOS = isIOS ?? Platform.isIOS;

  final EventChannel _eventChannel;
  final bool _isIOS;
  Stream<AudioRouteChange>? _changes;

  @override
  Stream<AudioRouteChange> get changes {
    if (!_isIOS) return _changes ??= const Stream.empty();
    return _changes ??= _eventChannel
        .receiveBroadcastStream()
        .map<AudioRouteChange>(
          (dynamic event) =>
              AudioRouteChange(AudioRouteChangeReason.fromString('$event')),
        )
        .handleError((Object _) {
      // Missing platform implementation (e.g. tests) — treat as
      // "no route events" rather than propagating the error.
    });
  }
}
