// `dev` flavor entrypoint. Wires `Telemetry.instance` to the
// OTel-backed implementation between storage init and `runApp`, so the
// first emitted span (`app.boot`) already lands in the SQLite outbox
// before any other layer starts.
//
// `package:opentelemetry` is reachable from this file and from
// `lib/core/observability/telemetry_otel.dart` only. The stable
// entrypoint has no transitive import path here.

import 'package:flutter/widgets.dart';
import 'package:voice_agent/app_main.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/core/observability/telemetry_otel.dart';

// Default Collector endpoint. Override with
// `--dart-define=OTEL_COLLECTOR=http://other.host:4318` when needed.
const _defaultCollector = 'http://laptop.lan:4318';
const _collectorEndpoint = String.fromEnvironment(
  'OTEL_COLLECTOR',
  defaultValue: _defaultCollector,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appMain(afterStorageInit: (storage) async {
    Telemetry.instance = await OtelTelemetry.boot(
      serviceName: 'voice-agent',
      serviceVersion: '1.0.0+1', // T3: hard-coded; T6 reads pubspec at gen time.
      collectorBaseUrl: Uri.parse(_collectorEndpoint),
      storage: storage,
    );
    Telemetry.instance.event('app.boot', attrs: const {
      'phase': 'post_storage_init',
    });
  });
}
