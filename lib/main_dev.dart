// `dev` flavor entrypoint. Reads the persisted dev-telemetry config
// (P039 T5c) and only boots the OTel-backed Telemetry when the user
// has it enabled and the Collector URL parses to a valid Uri.
// When disabled, the no-op default stays in place — telemetry off
// means telemetry off.
//
// `package:opentelemetry` is reachable from this file and from
// `lib/core/observability/telemetry_otel.dart` only. The stable
// entrypoint has no transitive import path here.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:voice_agent/app_main.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/core/observability/telemetry_native_bridge.dart';
import 'package:voice_agent/core/observability/telemetry_otel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appMain(afterStorageInit: (storage) async {
    final config = await AppConfigService().load();
    if (!config.devTelemetryEnabled) {
      if (kDebugMode) {
        debugPrint('main_dev: telemetry disabled by user — '
            'leaving NoopTelemetry in place.');
      }
      return;
    }
    final endpoint = Uri.tryParse(config.otelCollectorUrl);
    if (endpoint == null || !endpoint.isAbsolute) {
      if (kDebugMode) {
        debugPrint('main_dev: invalid Collector URL '
            '"${config.otelCollectorUrl}" — leaving NoopTelemetry.');
      }
      return;
    }
    Telemetry.instance = await OtelTelemetry.boot(
      serviceName: 'voice-agent',
      serviceVersion: '1.0.0+1', // T3: hard-coded; T6 reads pubspec at gen time.
      collectorBaseUrl: endpoint,
      storage: storage,
    );
    Telemetry.instance.event('app.boot', attrs: const {
      'phase': 'post_storage_init',
    });
    // P039 T5a — subscribe the native EventChannel that emits
    // `audio.session.*` and `audio.becoming_noisy`. Idempotent.
    // Process-scoped lifetime; nothing tears it down.
    TelemetryNativeBridge().start();
  });
}
