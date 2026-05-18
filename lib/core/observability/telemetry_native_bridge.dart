// P039 T5a — consumes the native EventChannel
// `com.voiceagent/telemetry_native_events` and re-emits each native
// payload as a standalone Telemetry event.
//
// The proposal's stretch goal is to pin the native events as span
// events on the active long-lived `hf.attach_stream` span. That
// requires extending the Telemetry facade with an "active span"
// concept; for v1 we emit as stand-alone events instead — the
// Grafana dashboard joins them by `service.name` + timestamp.
// Active-span pinning is tracked as a T5a v2 follow-up.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:voice_agent/core/observability/telemetry.dart';

/// Subscribes to the native event channel once at app boot. Lifetime
/// is the process — there is no `dispose()` because the singleton
/// outlives every widget tree.
class TelemetryNativeBridge {
  TelemetryNativeBridge({EventChannel? channel})
      : _channel = channel ??
            const EventChannel('com.voiceagent/telemetry_native_events');

  final EventChannel _channel;
  StreamSubscription<dynamic>? _subscription;

  /// Start listening. Idempotent — a second call is a no-op.
  void start() {
    if (_subscription != null) return;
    _subscription = _channel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) {
        // Surface bridge failures as telemetry itself, so the
        // dashboard tells us when the bridge is misbehaving rather
        // than going silent. Use the no-op-safe facade so this
        // emission is still safe on the stable flavour even if
        // someone wires the bridge there by mistake.
        Telemetry.instance.event('telemetry_native_bridge.error', attrs: {
          'message': e.toString(),
        });
      },
    );
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'];
    if (type is! String) return;

    final attrs = <String, Object?>{};
    final rawAttrs = raw['attrs'];
    if (rawAttrs is Map) {
      rawAttrs.forEach((key, value) {
        if (key is String) attrs[key] = value;
      });
    }
    // Carry the native-side wall clock through as an attribute so the
    // Grafana timeline can correlate against Dart-side spans even
    // when the channel-hop dispatch adds a few ms.
    final tsMs = raw['ts_ms'];
    if (tsMs is int) attrs['native_ts_ms'] = tsMs;

    Telemetry.instance.event(type, attrs: attrs);
  }
}
