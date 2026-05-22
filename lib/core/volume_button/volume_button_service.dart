import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:voice_agent/core/audio/audio_route_service.dart';
import 'package:voice_agent/core/volume_button/volume_button_port.dart';

/// Filters audio route-change `outputVolume` artefacts out of a raw
/// volume-button event stream (P042).
///
/// An iOS audio route change (AirPod removed, headphones un/plugged)
/// shifts `AVAudioSession.outputVolume`; the native KVO observer cannot
/// tell that apart from a real hardware press and emits a phantom
/// `up`/`down`. A phantom `down` would suspend the hands-free session.
///
/// A genuine press never coincides with a route change, while a
/// context-induced shift always does. Each candidate event is held for
/// [settleWindow]; if a route change arrives within that window — before
/// *or* after the event — the event is dropped. This closes both
/// delivery orderings (route-then-volume and volume-then-route).
///
/// Exposed for testing; used by [VolumeButtonService].
@visibleForTesting
Stream<VolumeButtonEvent> filterVolumeRouteArtefacts({
  required Stream<VolumeButtonEvent> raw,
  required Stream<AudioRouteChange> routeChanges,
  required Duration settleWindow,
}) {
  final out = StreamController<VolumeButtonEvent>.broadcast();
  var lastRouteChange = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? holdTimer;
  VolumeButtonEvent? held;
  StreamSubscription<AudioRouteChange>? routeSub;
  StreamSubscription<VolumeButtonEvent>? rawSub;

  void dropHeld() {
    holdTimer?.cancel();
    holdTimer = null;
    held = null;
  }

  out.onListen = () {
    routeSub = routeChanges.listen((_) {
      lastRouteChange = DateTime.now();
      // A route change cancels a volume event currently being held —
      // that event was the route change's `outputVolume` artefact.
      if (held != null) {
        debugPrint('[VolumeBtnDbg] dropped held $held — route change');
        dropHeld();
      }
    });
    rawSub = raw.listen((event) {
      // Look-back: a route change happened a moment ago → artefact.
      if (DateTime.now().difference(lastRouteChange) < settleWindow) {
        debugPrint('[VolumeBtnDbg] dropped $event — recent route change');
        return;
      }
      // Look-forward: hold briefly — a route change may still arrive.
      held = event;
      holdTimer?.cancel();
      holdTimer = Timer(settleWindow, () {
        final e = held;
        held = null;
        holdTimer = null;
        if (e != null) out.add(e);
      });
    });
  };
  out.onCancel = () {
    dropHeld();
    routeSub?.cancel();
    rawSub?.cancel();
    routeSub = null;
    rawSub = null;
  };
  return out.stream;
}

/// Platform-channel implementation of [VolumeButtonPort].
///
/// P042: the raw native event stream is passed through
/// [filterVolumeRouteArtefacts] so route-change `outputVolume` artefacts
/// are not misread as hardware presses.
class VolumeButtonService implements VolumeButtonPort {
  VolumeButtonService({
    required AudioRouteService audioRouteService,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Duration settleWindow = const Duration(milliseconds: 300),
  })  : _audioRouteService = audioRouteService,
        _settleWindow = settleWindow,
        _methodChannel = methodChannel ??
            const MethodChannel('com.voiceagent/volume_button'),
        _eventChannel = eventChannel ??
            const EventChannel('com.voiceagent/volume_button/events');

  final AudioRouteService _audioRouteService;
  final Duration _settleWindow;
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<VolumeButtonEvent>? _events;

  @override
  Stream<VolumeButtonEvent> get events => _events ??= filterVolumeRouteArtefacts(
        raw: _rawEvents(),
        routeChanges: _audioRouteService.changes,
        settleWindow: _settleWindow,
      );

  /// Raw, unfiltered volume events straight from the native EventChannel.
  Stream<VolumeButtonEvent> _rawEvents() {
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
