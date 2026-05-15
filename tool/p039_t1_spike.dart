// Copyright 2026 voice-agent. Apache-2.0.
//
// P039 T1 spike — verify the OTel Dart SDK can emit a span over OTLP/HTTP
// to a local Collector. Run the Collector first:
//
//   cd ops/dev && docker compose -f collector-only.docker-compose.yml up -d
//
// Then run this script:
//
//   dart run tool/p039_t1_spike.dart
//
// Expected: the script exits 0 and the Collector's stdout (visible via
// `docker logs voice-agent-otel-spike`) shows the span with name
// "hf.attach_stream" and resource attribute service.name=voice-agent-spike.

import 'dart:io';

import 'package:opentelemetry/api.dart' as api;
import 'package:opentelemetry/sdk.dart' as sdk;

Future<void> main() async {
  final exporter = sdk.CollectorExporter(
    Uri.parse('http://localhost:4318/v1/traces'),
    timeoutMilliseconds: 5000,
  );

  final processor = sdk.SimpleSpanProcessor(exporter);

  final provider = sdk.TracerProviderBase(
    processors: [processor],
    resource: sdk.Resource([
      api.Attribute.fromString('service.name', 'voice-agent-spike'),
      api.Attribute.fromString('service.version', '0.0.0-t1-spike'),
      api.Attribute.fromString('deployment.environment', 'dev'),
    ]),
  );

  final tracer = provider.getTracer(
    'p039-t1-spike',
    schemaUrl: 'https://opentelemetry.io/schemas/1.21.0',
  );

  stdout.writeln('emitting span hf.attach_stream → '
      'http://localhost:4318/v1/traces ...');

  final span = tracer.startSpan(
    'hf.attach_stream',
    attributes: [
      api.Attribute.fromBoolean('smoke', true),
      api.Attribute.fromString('source', 'p039_t1_spike.dart'),
    ],
  );

  // Simulate a tiny amount of work.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  span.addEvent('hf.chunk_received');
  span.end();

  // SimpleSpanProcessor is synchronous on end, but the HTTP POST inside
  // CollectorExporter.export uses `unawaited(_send(...))` — so we need to
  // give the future a moment to drain before shutdown.
  await Future<void>.delayed(const Duration(seconds: 1));

  provider.shutdown();

  stdout.writeln('done.');
}
