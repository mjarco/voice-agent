// OTel-backed Telemetry implementation. Imported ONLY from
// `lib/main_dev.dart`. The `stable` flavor's entrypoint
// (`lib/main_stable.dart`) does not reach this file, so
// `package:opentelemetry` is tree-shaken out of the stable AOT
// snapshot (verified in T1 spike: 466 KB delta, 0 `opentelemetry`
// strings hits — see docs/spikes/p039-t1-otel-viability.md).

import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

import 'telemetry.dart';

/// OTel-backed Telemetry. T3 wires the SDK with a synchronous
/// [otel_sdk.SimpleSpanProcessor] pointing at a Collector at
/// [collectorBaseUrl]. T4 replaces the processor with the durable
/// outbox-backed one.
class OtelTelemetry implements Telemetry {
  OtelTelemetry._(this._provider, this._tracer);

  /// Build and wire the OTel SDK. Call once from
  /// `lib/main_dev.dart` before `runApp`.
  ///
  /// [serviceName] is the OTel resource attribute identifying this app.
  /// [serviceVersion] is typically read from `pubspec.yaml`.
  /// [collectorBaseUrl] is the Collector base URL (no trailing slash);
  /// the SDK posts to `$collectorBaseUrl/v1/traces`.
  factory OtelTelemetry.boot({
    required String serviceName,
    required String serviceVersion,
    required Uri collectorBaseUrl,
  }) {
    final exporter = otel_sdk.CollectorExporter(
      collectorBaseUrl.resolve('/v1/traces'),
    );
    final processor = otel_sdk.SimpleSpanProcessor(exporter);
    final provider = otel_sdk.TracerProviderBase(
      processors: [processor],
      resource: otel_sdk.Resource([
        otel_api.Attribute.fromString('service.name', serviceName),
        otel_api.Attribute.fromString('service.version', serviceVersion),
        otel_api.Attribute.fromString('deployment.environment', 'dev'),
      ]),
    );
    final tracer = provider.getTracer(
      'voice-agent',
      schemaUrl: 'https://opentelemetry.io/schemas/1.21.0',
    );
    return OtelTelemetry._(provider, tracer);
  }

  final otel_sdk.TracerProviderBase _provider;
  final otel_api.Tracer _tracer;

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {
    // Stand-alone event: open and immediately close a zero-duration span
    // carrying the event name and attributes. T5a may route events as
    // span events on the active long-lived span when one exists.
    final span = _tracer.startSpan(
      name,
      attributes: _toOtelAttrs(attrs),
    );
    span.end();
  }

  @override
  TelemetrySpan span(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attrs = const {},
  }) {
    final span = _tracer.startSpan(
      name,
      kind: _mapKind(kind),
      attributes: _toOtelAttrs(attrs),
    );
    return _OtelSpan(span);
  }

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {
    // T3 renders counters as zero-duration spans tagged
    // `telemetry.kind=counter`. T6 swaps this for the OTel metrics
    // API once we exercise it.
    final mergedAttrs = {
      ...attrs,
      'telemetry.kind': 'counter',
      'delta': delta,
    };
    event(name, attrs: mergedAttrs);
  }

  @override
  void histogram(String name, num value,
      {Map<String, Object?> attrs = const {}}) {
    final mergedAttrs = {
      ...attrs,
      'telemetry.kind': 'histogram',
      'value': value,
    };
    event(name, attrs: mergedAttrs);
  }

  @override
  Future<void> flush() async {
    _provider.forceFlush();
  }
}

class _OtelSpan implements TelemetrySpan {
  _OtelSpan(this._span);
  final otel_api.Span _span;
  var _ended = false;

  @override
  void setAttr(String key, Object? value) {
    if (_ended) return;
    final attr = _toOtelAttr(key, value);
    if (attr != null) _span.setAttributes([attr]);
  }

  @override
  void addEvent(String name, {Map<String, Object?> attrs = const {}}) {
    if (_ended) return;
    _span.addEvent(name, attributes: _toOtelAttrs(attrs));
  }

  @override
  void end({SpanStatus status = SpanStatus.unset, String? message}) {
    if (_ended) return;
    _ended = true;
    switch (status) {
      case SpanStatus.ok:
        _span.setStatus(otel_api.StatusCode.ok, message ?? '');
      case SpanStatus.error:
        _span.setStatus(otel_api.StatusCode.error, message ?? '');
      case SpanStatus.unset:
        break;
    }
    _span.end();
  }
}

otel_api.SpanKind _mapKind(SpanKind k) {
  switch (k) {
    case SpanKind.internal:
      return otel_api.SpanKind.internal;
    case SpanKind.server:
      return otel_api.SpanKind.server;
    case SpanKind.client:
      return otel_api.SpanKind.client;
    case SpanKind.producer:
      return otel_api.SpanKind.producer;
    case SpanKind.consumer:
      return otel_api.SpanKind.consumer;
  }
}

List<otel_api.Attribute> _toOtelAttrs(Map<String, Object?> attrs) {
  final out = <otel_api.Attribute>[];
  attrs.forEach((k, v) {
    final attr = _toOtelAttr(k, v);
    if (attr != null) out.add(attr);
  });
  return out;
}

otel_api.Attribute? _toOtelAttr(String key, Object? value) {
  if (value == null) return null;
  if (value is String) return otel_api.Attribute.fromString(key, value);
  if (value is bool) return otel_api.Attribute.fromBoolean(key, value);
  if (value is int) return otel_api.Attribute.fromInt(key, value);
  if (value is double) return otel_api.Attribute.fromDouble(key, value);
  return otel_api.Attribute.fromString(key, value.toString());
}
