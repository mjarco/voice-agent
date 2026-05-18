// P039 T5a — TelemetryNativeBridge consumes native events from the
// `com.voiceagent/telemetry_native_events` EventChannel and emits
// them as Telemetry events. We drive the EventChannel via the test
// binary messenger so we don't need any native code on the test side.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/core/observability/telemetry_native_bridge.dart';

const _channelName = 'com.voiceagent/telemetry_native_events';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Recording recording;

  setUp(() {
    recording = _Recording();
    Telemetry.instance = recording;
  });

  tearDown(() {
    Telemetry.instance = const NoopTelemetry();
  });

  /// Fires one event on the named channel from the "native" side.
  Future<void> sendNativeEvent(Map<String, dynamic> payload) async {
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    final envelope = codec.encodeSuccessEnvelope(payload);
    await messenger.handlePlatformMessage(_channelName, envelope, (_) {});
  }

  test('emits a Telemetry event with the native type and attrs', () async {
    TelemetryNativeBridge().start();
    // Give the broadcast stream's subscriber registration one tick to
    // attach before we fire the event.
    await Future<void>.delayed(Duration.zero);

    await sendNativeEvent({
      'type': 'audio.session.interruption_began',
      'ts_ms': 1715980000000,
      'attrs': {'reason': 1},
    });
    await Future<void>.delayed(Duration.zero);

    expect(recording.events, hasLength(1));
    expect(recording.events.single.name, 'audio.session.interruption_began');
    expect(recording.events.single.attrs['reason'], 1);
    expect(recording.events.single.attrs['native_ts_ms'], 1715980000000);
  });

  test('ignores payloads missing a `type` field', () async {
    TelemetryNativeBridge().start();
    await Future<void>.delayed(Duration.zero);

    await sendNativeEvent({'attrs': {'reason': 1}});
    await Future<void>.delayed(Duration.zero);
    expect(recording.events, isEmpty);
  });

  test('ignores payloads where `type` is not a String', () async {
    TelemetryNativeBridge().start();
    await Future<void>.delayed(Duration.zero);

    await sendNativeEvent({'type': 42, 'attrs': {}});
    await Future<void>.delayed(Duration.zero);
    expect(recording.events, isEmpty);
  });

  test('tolerates payloads with no attrs key', () async {
    TelemetryNativeBridge().start();
    await Future<void>.delayed(Duration.zero);

    await sendNativeEvent({
      'type': 'audio.becoming_noisy',
      'ts_ms': 1715980000000,
    });
    await Future<void>.delayed(Duration.zero);

    expect(recording.events, hasLength(1));
    expect(recording.events.single.name, 'audio.becoming_noisy');
    expect(recording.events.single.attrs['native_ts_ms'], 1715980000000);
  });

  test('start() is idempotent — second call does not double-subscribe',
      () async {
    final bridge = TelemetryNativeBridge();
    bridge.start();
    bridge.start();
    await Future<void>.delayed(Duration.zero);

    await sendNativeEvent({'type': 'audio.becoming_noisy', 'ts_ms': 0});
    await Future<void>.delayed(Duration.zero);

    expect(recording.events, hasLength(1),
        reason: 'a second start() must not duplicate emissions');
  });
}

class _Recording implements Telemetry {
  final List<_Event> events = [];

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {
    events.add(_Event(name, Map<String, Object?>.from(attrs)));
  }

  @override
  TelemetrySpan span(String name,
          {SpanKind kind = SpanKind.internal,
          Map<String, Object?> attrs = const {}}) =>
      const NoopTelemetry().span(name, kind: kind, attrs: attrs);

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {}

  @override
  void histogram(String name, num value,
      {Map<String, Object?> attrs = const {}}) {}

  @override
  Future<void> flush() async {}
}

class _Event {
  _Event(this.name, this.attrs);
  final String name;
  final Map<String, Object?> attrs;
}
