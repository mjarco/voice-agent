import 'package:flutter/services.dart';
import 'package:voice_agent/core/audio/audio_route_service.dart';

/// [AudioRouteService] backed by the
/// `com.voiceagent/audio_session/route_changes` EventChannel, registered
/// on iOS by `AudioSessionBridge`.
///
/// On platforms that do not implement the channel (Android, tests), the
/// first listen surfaces a `MissingPluginException`; it is swallowed so
/// the stream is simply silent rather than crashing.
class PlatformAudioRouteService implements AudioRouteService {
  PlatformAudioRouteService({EventChannel? eventChannel})
      : _eventChannel = eventChannel ??
            const EventChannel('com.voiceagent/audio_session/route_changes');

  final EventChannel _eventChannel;
  Stream<AudioRouteChange>? _changes;

  @override
  Stream<AudioRouteChange> get changes {
    return _changes ??= _eventChannel
        .receiveBroadcastStream()
        .map<AudioRouteChange>(
          (dynamic event) =>
              AudioRouteChange(AudioRouteChangeReason.fromString('$event')),
        )
        .handleError((Object _) {
      // Missing platform implementation (Android / tests) — treat as
      // "no route events" rather than propagating the error.
    });
  }
}
