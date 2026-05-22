import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audio_route_service.dart';
import 'package:voice_agent/core/volume_button/volume_button_port.dart';
import 'package:voice_agent/core/volume_button/volume_button_service.dart';

void main() {
  group('filterVolumeRouteArtefacts (P042)', () {
    const window = Duration(milliseconds: 80);

    late StreamController<VolumeButtonEvent> raw;
    late StreamController<AudioRouteChange> routes;
    late List<VolumeButtonEvent> got;
    late StreamSubscription<VolumeButtonEvent> sub;

    setUp(() {
      raw = StreamController<VolumeButtonEvent>();
      routes = StreamController<AudioRouteChange>.broadcast();
      got = <VolumeButtonEvent>[];
      sub = filterVolumeRouteArtefacts(
        raw: raw.stream,
        routeChanges: routes.stream,
        settleWindow: window,
      ).listen(got.add);
    });

    tearDown(() async {
      await sub.cancel();
      await raw.close();
      await routes.close();
    });

    void route() => routes
        .add(const AudioRouteChange(AudioRouteChangeReason.oldDeviceUnavailable));

    test('emits a volume event when no route change occurs', () async {
      raw.add(VolumeButtonEvent.down);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(got, [VolumeButtonEvent.down]);
    });

    test('drops a volume event when a route change follows within the window',
        () async {
      raw.add(VolumeButtonEvent.down);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      route(); // arrives while the event is still held
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(got, isEmpty, reason: 'volume-then-route artefact suppressed');
    });

    test('drops a volume event that arrives just after a route change',
        () async {
      route();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      raw.add(VolumeButtonEvent.down); // KVO delivered after the notification
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(got, isEmpty, reason: 'route-then-volume artefact suppressed');
    });

    test('emits a volume event that arrives long after a route change',
        () async {
      route();
      await Future<void>.delayed(const Duration(milliseconds: 200)); // > window
      raw.add(VolumeButtonEvent.up);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(got, [VolumeButtonEvent.up], reason: 'genuine press, not artefact');
    });
  });
}
