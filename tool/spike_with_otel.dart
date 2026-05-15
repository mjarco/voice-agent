// P039 T1 spike — entrypoint that imports OTel. Compared against
// spike_without_otel.dart to measure the AOT tree-shake delta.
//
// Build (compare libapp.so size after):
//
//   flutter build apk --release --flavor dev    --target tool/spike_with_otel.dart
//   flutter build apk --release --flavor stable --target tool/spike_without_otel.dart
//
// Then compare `build/app/intermediates/merged_native_libs/*/lib/arm64-v8a/libapp.so`.

import 'package:flutter/material.dart';
import 'package:opentelemetry/api.dart' as api;
import 'package:opentelemetry/sdk.dart' as sdk;

void main() {
  final exporter = sdk.CollectorExporter(
    Uri.parse('http://localhost:4318/v1/traces'),
  );
  final processor = sdk.SimpleSpanProcessor(exporter);
  final provider = sdk.TracerProviderBase(processors: [processor]);
  final tracer = provider.getTracer('spike-with-otel');
  tracer
      .startSpan('spike_boot', attributes: [
        api.Attribute.fromString('source', 'spike_with_otel.dart'),
      ])
      .end();

  runApp(const _SpikeApp());
}

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('spike with OTel'))),
    );
  }
}
