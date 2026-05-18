// P039 T4b — encode an ended OTel span to OTLP/HTTP JSON bytes.
//
// Produces the same payload shape the dev-flavor Collector accepts on
// /v1/traces (verified end-to-end in the T1 spike). The output is one
// ExportTraceServiceRequest envelope containing a single span — small
// enough to persist row-by-row in the SQLite outbox.
//
// We use the JSON variant rather than protobuf because:
//  - Storage payloads are human-inspectable for diagnostics.
//  - Lower implementation cost (no protobuf transitive churn).
//  - The Collector accepts both interchangeably on :4318.

import 'dart:convert';
import 'dart:typed_data';

import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

/// Encode a single ended span to an OTLP/HTTP JSON `ExportTraceServiceRequest`
/// envelope. Returns the JSON-UTF-8 bytes ready to drop into the outbox
/// payload column.
Uint8List encodeSpanToOtlpJsonBytes(otel_sdk.ReadOnlySpan span) {
  final envelope = {
    'resourceSpans': [
      {
        'resource': _encodeResource(span.resource),
        'scopeSpans': [
          {
            'scope': {
              'name': span.instrumentationScope.name,
              if (span.instrumentationScope.version.isNotEmpty)
                'version': span.instrumentationScope.version,
            },
            'spans': [_encodeSpan(span)],
          },
        ],
      },
    ],
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

Map<String, Object?> _encodeResource(otel_sdk.Resource resource) {
  return {
    'attributes': _encodeAttributes(resource.attributes),
  };
}

Map<String, Object?> _encodeSpan(otel_sdk.ReadOnlySpan span) {
  final ctx = span.spanContext;
  final endTime = span.endTime;
  return {
    'traceId': ctx.traceId.toString(),
    'spanId': ctx.spanId.toString(),
    if (span.parentSpanId.isValid)
      'parentSpanId': span.parentSpanId.toString(),
    'name': span.name,
    'kind': _encodeKind(span.kind),
    'startTimeUnixNano': span.startTime.toString(),
    'endTimeUnixNano': (endTime ?? span.startTime).toString(),
    'attributes': _encodeAttributes(span.attributes),
    'events': span.events.map(_encodeEvent).toList(),
    'status': _encodeStatus(span.status),
  };
}

List<Map<String, Object?>> _encodeAttributes(otel_sdk.Attributes attrs) {
  final out = <Map<String, Object?>>[];
  for (final key in attrs.keys) {
    final value = attrs.get(key);
    out.add({
      'key': key,
      'value': _encodeAttributeValue(value),
    });
  }
  return out;
}

Map<String, Object?> _encodeEvent(otel_api.SpanEvent event) {
  return {
    'timeUnixNano': event.timestamp.toString(),
    'name': event.name,
    'attributes': _encodeAttributeIterable(event.attributes),
  };
}

/// SpanEvent.attributes is an `Iterable<Attribute>` rather than the
/// `Attributes` collection used on spans themselves.
List<Map<String, Object?>> _encodeAttributeIterable(
    Iterable<otel_api.Attribute> attrs) {
  final out = <Map<String, Object?>>[];
  for (final a in attrs) {
    out.add({
      'key': a.key,
      'value': _encodeAttributeValue(a.value),
    });
  }
  return out;
}

Map<String, Object?> _encodeStatus(otel_api.SpanStatus status) {
  return {
    'code': _mapStatusCode(status.code),
    if (status.description.isNotEmpty) 'message': status.description,
  };
}

int _mapStatusCode(otel_api.StatusCode code) {
  switch (code) {
    case otel_api.StatusCode.ok:
      return 1;
    case otel_api.StatusCode.error:
      return 2;
    case otel_api.StatusCode.unset:
      return 0;
  }
}

int _encodeKind(otel_api.SpanKind kind) {
  switch (kind) {
    case otel_api.SpanKind.internal:
      return 1;
    case otel_api.SpanKind.server:
      return 2;
    case otel_api.SpanKind.client:
      return 3;
    case otel_api.SpanKind.producer:
      return 4;
    case otel_api.SpanKind.consumer:
      return 5;
  }
}

/// OTel AnyValue tagged-union — pick the variant by Dart type.
Map<String, Object?> _encodeAttributeValue(Object? value) {
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'boolValue': value};
  // Per OTel JSON spec, int64 is encoded as a *string* to dodge
  // JS number-precision loss. We do the same.
  if (value is int) return {'intValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is List<String>) {
    return {
      'arrayValue': {
        'values': value.map((s) => {'stringValue': s}).toList(),
      }
    };
  }
  if (value is List<bool>) {
    return {
      'arrayValue': {
        'values': value.map((b) => {'boolValue': b}).toList(),
      }
    };
  }
  if (value is List<int>) {
    return {
      'arrayValue': {
        'values':
            value.map((i) => {'intValue': i.toString()}).toList(),
      }
    };
  }
  if (value is List<double>) {
    return {
      'arrayValue': {
        'values': value.map((d) => {'doubleValue': d}).toList(),
      }
    };
  }
  // Fallback: stringify whatever it is.
  return {'stringValue': value?.toString() ?? ''};
}
