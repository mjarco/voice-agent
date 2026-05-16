import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/observability/telemetry.dart';

void main() {
  group('Telemetry facade — default behaviour', () {
    test('Telemetry.instance defaults to NoopTelemetry at static init', () {
      expect(Telemetry.instance, isA<NoopTelemetry>());
    });

    test('NoopTelemetry.event is a tolerant no-op', () {
      const t = NoopTelemetry();
      expect(() => t.event('anything'), returnsNormally);
      expect(() => t.event('with-attrs', attrs: const {'k': 'v'}),
          returnsNormally);
    });

    test('NoopTelemetry.span returns a span whose lifecycle is a no-op', () {
      const t = NoopTelemetry();
      final span = t.span('test', attrs: const {'a': 1});
      expect(() {
        span.setAttr('b', 'x');
        span.addEvent('mid', attrs: const {'k': true});
        span.end();
        // Calls after end are silently ignored.
        span.setAttr('c', 2);
        span.addEvent('post-end');
        span.end(status: SpanStatus.error, message: 'noop');
      }, returnsNormally);
    });

    test('NoopTelemetry.counter and histogram are no-ops', () {
      const t = NoopTelemetry();
      expect(() => t.counter('chunks', delta: 7), returnsNormally);
      expect(() => t.histogram('latency_ms', 42.5), returnsNormally);
    });

    test('NoopTelemetry.flush resolves immediately', () async {
      const t = NoopTelemetry();
      await expectLater(t.flush(), completes);
    });
  });

  group('Telemetry facade — test-only recording subtype', () {
    test('a recording subtype can be injected for assertions', () {
      final recording = _RecordingTelemetry();
      Telemetry.instance = recording;
      addTearDown(() => Telemetry.instance = const NoopTelemetry());

      Telemetry.instance.event('mic-silent', attrs: const {'reason': 'test'});
      Telemetry.instance.counter('hf.chunk_received');

      expect(recording.events, hasLength(1));
      expect(recording.events.single.name, 'mic-silent');
      expect(recording.events.single.attrs, containsPair('reason', 'test'));
      expect(recording.counters, hasLength(1));
      expect(recording.counters.single.name, 'hf.chunk_received');
      expect(recording.counters.single.delta, 1);
    });
  });
}

class _RecordingTelemetry implements Telemetry {
  final List<_Event> events = [];
  final List<_Counter> counters = [];

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {
    events.add(_Event(name, attrs));
  }

  @override
  TelemetrySpan span(String name,
      {SpanKind kind = SpanKind.internal,
      Map<String, Object?> attrs = const {}}) {
    return const NoopTelemetry().span(name, kind: kind, attrs: attrs);
  }

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {
    counters.add(_Counter(name, delta, attrs));
  }

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

class _Counter {
  _Counter(this.name, this.delta, this.attrs);
  final String name;
  final int delta;
  final Map<String, Object?> attrs;
}
