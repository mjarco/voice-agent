// P039 T4b — SpanProcessor that persists each ended span to the
// SQLite outbox before returning. Replaces SimpleSpanProcessor +
// CollectorExporter as the active export path on the dev flavor
// once T4b-2 wires it in. The TelemetryFlushWorker then drains the
// outbox over OTLP/HTTP.
//
// Design notes:
//
// * The SpanProcessor interface's onEnd is synchronous (returns void).
//   SQLite writes through sqflite are async. We enqueue the encode +
//   append immediately (no in-memory batching window like the default
//   BatchSpanProcessor) and let the storage append complete on the
//   next microtask. The window between span.end() and the row landing
//   on disk is single-digit milliseconds — orders of magnitude smaller
//   than BatchSpanProcessor's 10s window and acceptable for the
//   force-quit durability AC.
//
// * Failures in the persist path are logged via [onPersistError] if
//   provided, otherwise debugPrint'd in kDebugMode. They are NOT
//   re-raised; the caller's `span.end()` cannot meaningfully react.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;
import 'package:voice_agent/core/observability/otlp_encoder.dart';
import 'package:voice_agent/core/observability/telemetry_outbox_row.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

class DurableSpanProcessor implements otel_sdk.SpanProcessor {
  DurableSpanProcessor({
    required StorageService storage,
    this.onPersistError,
  }) : _storage = storage;

  final StorageService _storage;

  /// Optional hook for observing persist failures. If null, errors are
  /// logged via debugPrint in kDebugMode only.
  final void Function(Object error, StackTrace stack)? onPersistError;

  /// Futures returned by in-flight persist calls — kept so [forceFlush]
  /// can await them. The set is intentionally unbounded; under the
  /// expected event rate (~50 spans/min peak per P039 Resource cost),
  /// it never grows large.
  final Set<Future<void>> _pending = {};

  @override
  void onStart(otel_sdk.ReadWriteSpan span, otel_api.Context parentContext) {
    // No-op. We persist on end.
  }

  @override
  void onEnd(otel_sdk.ReadOnlySpan span) {
    final future = _persist(span);
    _pending.add(future);
    future.whenComplete(() => _pending.remove(future));
  }

  Future<void> _persist(otel_sdk.ReadOnlySpan span) async {
    try {
      final payload = encodeSpanToOtlpJsonBytes(span);
      await _storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload,
      );
    } catch (e, st) {
      final handler = onPersistError;
      if (handler != null) {
        handler(e, st);
      } else if (kDebugMode) {
        debugPrint('DurableSpanProcessor.persist failed: $e');
      }
    }
  }

  @override
  void forceFlush() {
    // Best-effort: drain the currently-known in-flight persists.
    // We do not await here (interface returns void); callers that need
    // a deterministic flush call [drain] below before tearing down.
    // Most callers (forceFlush from app lifecycle hooks) just want a
    // hint to start writing.
  }

  /// Await every persist future that is currently in flight. Use from
  /// app-shutdown hooks where you actually want to block on the
  /// outbox catching up.
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      final snapshot = List<Future<void>>.from(_pending);
      await Future.wait(snapshot);
    }
  }

  @override
  void shutdown() {
    // No-op; the storage outlives the processor. forceFlush + drain
    // are the explicit teardown sequence.
  }
}
