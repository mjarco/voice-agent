// P039 T4b — drain the telemetry_outbox over OTLP/HTTP.
//
// Wakes every [foregroundInterval] (default 10s) and claims up to
// [batchSize] rows due for flush, posts each row's payload to the
// matching Collector endpoint (/v1/traces vs /v1/metrics), and:
//   - 2xx       -> delete row
//   - ApiTransientFailure (408/429/5xx, network) -> mark for retry
//     with exponential back-off (capped at 5 min)
//   - ApiPermanentFailure (other 4xx) -> drop row + bump drop counter
//
// Single-flight via the storage layer's transactional claim
// (`claimDueTelemetryRows`). Boot recovery via
// `releaseStaleTelemetryClaims`.
//
// Status classification delegated to `ApiClient.classifyStatusCode`
// per ADR-OBS-001 §7 — no parallel OTLP classifier.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/observability/telemetry_outbox_row.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

/// Outcome of one flush tick. Useful for tests that drive the worker
/// manually via [flushOnce].
class TelemetryFlushReport {
  const TelemetryFlushReport({
    required this.claimed,
    required this.deleted,
    required this.retried,
    required this.dropped,
  });

  final int claimed;
  final int deleted;
  final int retried;
  final int dropped;

  @override
  String toString() =>
      'TelemetryFlushReport(claimed=$claimed deleted=$deleted '
      'retried=$retried dropped=$dropped)';
}

class TelemetryFlushWorker {
  TelemetryFlushWorker({
    required StorageService storage,
    required Uri collectorBaseUrl,
    http.Client? httpClient,
    ApiClient? classifier,
    Duration foregroundInterval = const Duration(seconds: 10),
    Duration backgroundInterval = const Duration(seconds: 60),
    int batchSize = 50,
    int maxAttempts = 10,
    Duration maxBackoff = const Duration(minutes: 5),
  })  : _storage = storage,
        _baseUrl = collectorBaseUrl,
        _http = httpClient ?? http.Client(),
        _classifier = classifier ?? ApiClient(),
        _foregroundInterval = foregroundInterval,
        _backgroundInterval = backgroundInterval,
        _batchSize = batchSize,
        _maxAttempts = maxAttempts,
        _maxBackoff = maxBackoff;

  final StorageService _storage;
  final Uri _baseUrl;
  final http.Client _http;
  final ApiClient _classifier;
  final Duration _foregroundInterval;
  final Duration _backgroundInterval;
  final int _batchSize;
  final int _maxAttempts;
  final Duration _maxBackoff;

  Timer? _timer;
  bool _flushing = false;
  bool _isForeground = true;

  /// Start the timer. Idempotent. Releases stale claims left over from
  /// a previous process's crashed flusher before scheduling the first
  /// tick.
  Future<void> start() async {
    if (_timer != null) return;
    final released = await _storage.releaseStaleTelemetryClaims();
    if (kDebugMode && released > 0) {
      debugPrint('TelemetryFlushWorker.start: released $released stale claims');
    }
    _schedule();
  }

  /// Update the foreground/background cadence in response to app
  /// lifecycle changes. Re-schedules the timer.
  void setForeground(bool foreground) {
    if (_isForeground == foreground) return;
    _isForeground = foreground;
    if (_timer != null) {
      _timer!.cancel();
      _schedule();
    }
  }

  /// Stop the timer. Does NOT drain in-flight HTTP calls.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Run one flush tick now and return the outcome. Used by tests and
  /// by app-shutdown hooks that want a synchronous drain.
  Future<TelemetryFlushReport> flushOnce() async {
    if (_flushing) {
      return const TelemetryFlushReport(
          claimed: 0, deleted: 0, retried: 0, dropped: 0);
    }
    _flushing = true;
    try {
      final rows = await _storage.claimDueTelemetryRows(limit: _batchSize);
      if (rows.isEmpty) {
        return const TelemetryFlushReport(
            claimed: 0, deleted: 0, retried: 0, dropped: 0);
      }
      var deleted = 0;
      var retried = 0;
      var dropped = 0;
      for (final row in rows) {
        final outcome = await _postOne(row);
        switch (outcome) {
          case _Outcome.success:
            await _storage.deleteTelemetryRows([row.id]);
            deleted++;
          case _Outcome.transient:
            if (row.attempts + 1 >= _maxAttempts) {
              await _storage.deleteTelemetryRows([row.id]);
              dropped++;
            } else {
              await _storage.markTelemetryRetry(
                id: row.id,
                nextAttemptAt:
                    DateTime.now().add(_backoffFor(row.attempts + 1)),
                lastError: _lastError,
              );
              retried++;
            }
          case _Outcome.permanent:
            await _storage.deleteTelemetryRows([row.id]);
            dropped++;
        }
      }
      return TelemetryFlushReport(
        claimed: rows.length,
        deleted: deleted,
        retried: retried,
        dropped: dropped,
      );
    } finally {
      _flushing = false;
    }
  }

  Duration _backoffFor(int attempts) {
    // 2^attempts seconds, capped.
    final seconds = (1 << attempts).clamp(1, _maxBackoff.inSeconds);
    return Duration(seconds: seconds);
  }

  String _lastError = '';

  Future<_Outcome> _postOne(TelemetryOutboxRow row) async {
    final endpoint = _endpointFor(row.signalKind);
    try {
      final response = await _http.post(
        endpoint,
        headers: const {'Content-Type': 'application/json'},
        body: row.payload,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _Outcome.success;
      }
      final classified = _classifier.classifyStatusCode(
        response.statusCode,
        response.reasonPhrase,
      );
      switch (classified) {
        case ApiTransientFailure(:final reason):
          _lastError = reason;
          return _Outcome.transient;
        case ApiPermanentFailure(:final statusCode, :final message):
          _lastError = 'HTTP $statusCode: $message';
          return _Outcome.permanent;
        case ApiSuccess() || ApiNotConfigured():
          _lastError = 'unexpected classification: $classified';
          return _Outcome.permanent;
      }
    } on http.ClientException catch (e) {
      _lastError = 'network: $e';
      return _Outcome.transient;
    } on TimeoutException catch (e) {
      _lastError = 'timeout: $e';
      return _Outcome.transient;
    } catch (e) {
      // Anything else (encoding, DNS, etc.) — treat as transient. If
      // it's actually permanent it will be dropped after maxAttempts.
      _lastError = 'unknown: $e';
      return _Outcome.transient;
    }
  }

  Uri _endpointFor(TelemetrySignalKind kind) {
    switch (kind) {
      case TelemetrySignalKind.trace:
        return _baseUrl.resolve('/v1/traces');
      case TelemetrySignalKind.metric:
        return _baseUrl.resolve('/v1/metrics');
    }
  }

  void _schedule() {
    final interval = _isForeground ? _foregroundInterval : _backgroundInterval;
    _timer = Timer.periodic(interval, (_) => flushOnce());
  }

  /// Helper for the chunky drop case — exposes the dropped-counter
  /// signal name (used to populate Telemetry.counter from a higher
  /// layer if telemetry-on-telemetry is wired). Worker itself does
  /// not emit telemetry (avoid recursion).
  static String get dropCounterName => 'telemetry_drop';
}

enum _Outcome { success, transient, permanent }
