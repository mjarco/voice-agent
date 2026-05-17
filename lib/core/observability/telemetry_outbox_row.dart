// P039 T4 — durable OTLP outbox row model.
//
// Each row carries one OTLP/JSON ExportRequest payload that the flush
// worker will POST to the Collector. Persisted by DurableSpanProcessor
// on every span.end() so force-quit does not lose finished spans.
//
// Schema lives in lib/core/storage/sqlite_storage_service.dart
// (migration v1→v2).

import 'dart:typed_data';

/// Signal kind for an outbox row. Determines the OTLP endpoint path
/// (`/v1/traces` vs `/v1/metrics`). v1 emits only traces; metrics path
/// is wired in T6.
enum TelemetrySignalKind {
  trace('trace'),
  metric('metric');

  const TelemetrySignalKind(this.dbValue);
  final String dbValue;

  static TelemetrySignalKind fromDb(String value) =>
      values.firstWhere((k) => k.dbValue == value);
}

/// One row in `telemetry_outbox`. Immutable view; mutations go through
/// StorageService methods.
class TelemetryOutboxRow {
  const TelemetryOutboxRow({
    required this.id,
    required this.signalKind,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    required this.nextAttemptAt,
    this.claimedAt,
    this.lastError,
  });

  final int id;
  final TelemetrySignalKind signalKind;
  final Uint8List payload;
  final DateTime createdAt;
  final int attempts;
  final DateTime nextAttemptAt;
  final DateTime? claimedAt;
  final String? lastError;

  factory TelemetryOutboxRow.fromMap(Map<String, Object?> m) {
    return TelemetryOutboxRow(
      id: m['id']! as int,
      signalKind: TelemetrySignalKind.fromDb(m['signal_kind']! as String),
      payload: m['payload']! as Uint8List,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int),
      attempts: m['attempts']! as int,
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
          m['next_attempt_at']! as int),
      claimedAt: m['claimed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['claimed_at']! as int),
      lastError: m['last_error'] as String?,
    );
  }
}

/// Retention caps per `TelemetrySignalKind`. Enforced on insert by
/// `StorageService.appendTelemetryRow`. See P039 §Offline buffering.
const Map<TelemetrySignalKind, int> kTelemetryRetentionByKind = {
  TelemetrySignalKind.trace: 3000,
  TelemetrySignalKind.metric: 2000,
};

/// Maximum age before a row is dropped regardless of cap.
const Duration kTelemetryMaxAge = Duration(days: 7);

/// A claimed row may not be released by another claim attempt sooner
/// than this. On boot, stale claims older than this are released so
/// the next worker can pick them up.
const Duration kTelemetryClaimTtl = Duration(minutes: 5);
