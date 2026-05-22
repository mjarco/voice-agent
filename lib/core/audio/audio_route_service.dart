/// Reason an iOS audio route changed, mirrored from
/// `AVAudioSession.RouteChangeReason`. Emitted by `AudioSessionBridge`
/// over the `com.voiceagent/audio_session/route_changes` EventChannel.
enum AudioRouteChangeReason {
  newDeviceAvailable,
  oldDeviceUnavailable,
  routeConfigurationChange,
  categoryChange,
  routeOverride,
  wakeFromSleep,
  noSuitableRouteForCategory,
  unknown;

  /// True for reasons that can change the **input** route and therefore
  /// require the capture stream to be re-acquired.
  ///
  /// `categoryChange` is excluded: it is usually the app's own doing
  /// (starting `.playAndRecord`) and reacting to it would cause a
  /// restart loop. `routeOverride` is output-only.
  bool get affectsInputRoute =>
      this == newDeviceAvailable ||
      this == oldDeviceUnavailable ||
      this == routeConfigurationChange;

  /// Maps the raw string sent by the native bridge to an enum value.
  /// Unrecognised values map to [unknown].
  static AudioRouteChangeReason fromString(String raw) {
    switch (raw) {
      case 'newDeviceAvailable':
        return AudioRouteChangeReason.newDeviceAvailable;
      case 'oldDeviceUnavailable':
        return AudioRouteChangeReason.oldDeviceUnavailable;
      case 'routeConfigurationChange':
        return AudioRouteChangeReason.routeConfigurationChange;
      case 'categoryChange':
        return AudioRouteChangeReason.categoryChange;
      case 'override':
        return AudioRouteChangeReason.routeOverride;
      case 'wakeFromSleep':
        return AudioRouteChangeReason.wakeFromSleep;
      case 'noSuitableRouteForCategory':
        return AudioRouteChangeReason.noSuitableRouteForCategory;
      default:
        return AudioRouteChangeReason.unknown;
    }
  }
}

/// A single audio route change event.
class AudioRouteChange {
  const AudioRouteChange(this.reason);

  final AudioRouteChangeReason reason;

  @override
  String toString() => 'AudioRouteChange(${reason.name})';
}

/// Port for observing iOS audio route changes (P042).
///
/// The hands-free capture pipeline ([HandsFreeOrchestrator]) listens to
/// this so it can re-acquire the microphone stream when the input route
/// changes. Removing an AirPod or un-plugging headphones otherwise
/// silently kills capture: the `record` plugin's PCM stream stops
/// delivering audio without emitting `onError` or `onDone`.
abstract interface class AudioRouteService {
  /// Broadcast stream of route changes.
  ///
  /// iOS emits on every `AVAudioSession.routeChangeNotification`.
  /// Android emits nothing (the `record` plugin handles route changes
  /// internally there) — the stream simply stays silent.
  Stream<AudioRouteChange> get changes;
}
