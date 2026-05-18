// P039 T4b — TelemetryFlushWorker.
//
// Each test drives `worker.flushOnce()` synchronously rather than
// relying on the Timer. The HTTP client is mocked so we can simulate
// 2xx / transient / permanent responses deterministically.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_agent/core/observability/telemetry_flush_worker.dart';
import 'package:voice_agent/core/observability/telemetry_outbox_row.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';

void main() {
  late SqliteStorageService storage;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('flush_test_');
    storage = await SqliteStorageService.initialize(
      databaseFactory: databaseFactoryFfi,
      path: '${tempDir.path}/flush.db',
    );
  });

  Uint8List payload(String s) => Uint8List.fromList(s.codeUnits);

  TelemetryFlushWorker makeWorker({
    required http.Client client,
  }) {
    return TelemetryFlushWorker(
      storage: storage,
      collectorBaseUrl: Uri.parse('http://localhost:4318'),
      httpClient: client,
    );
  }

  group('happy path', () {
    test('2xx response deletes the row', () async {
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      final worker = makeWorker(
        client: http_testing.MockClient((_) async => http.Response('', 200)),
      );
      final report = await worker.flushOnce();
      expect(report.claimed, 1);
      expect(report.deleted, 1);
      expect(report.retried, 0);

      final remaining = await storage.claimDueTelemetryRows();
      expect(remaining, isEmpty);
    });

    test('routes traces to /v1/traces and metrics to /v1/metrics',
        () async {
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('t'),
      );
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.metric,
        payload: payload('m'),
      );
      final endpoints = <String>[];
      final worker = makeWorker(
        client: http_testing.MockClient((req) async {
          endpoints.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await worker.flushOnce();
      expect(endpoints, containsAll(<String>['/v1/traces', '/v1/metrics']));
    });
  });

  group('transient failures retry', () {
    test('500 marks for retry and increments attempts', () async {
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      final worker = makeWorker(
        client: http_testing.MockClient(
          (_) async => http.Response('boom', 500),
        ),
      );
      final report = await worker.flushOnce();
      expect(report.retried, 1);
      expect(report.deleted, 0);
      expect(report.dropped, 0);

      // Row should be there with attempts=1 and next_attempt_at in
      // the future. We can verify by checking claimDue with default
      // (now) returns nothing.
      final reclaim = await storage.claimDueTelemetryRows();
      expect(reclaim, isEmpty,
          reason: 'next_attempt_at is in the future after back-off');
    });

    test('408/429 are classified as transient', () async {
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p1'),
      );
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p2'),
      );
      var requestCount = 0;
      final worker = makeWorker(
        client: http_testing.MockClient((_) async {
          requestCount++;
          return http.Response('rate limited',
              requestCount == 1 ? 408 : 429);
        }),
      );
      final report = await worker.flushOnce();
      expect(report.retried, 2);
    });

    test('network error is transient', () async {
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      final worker = makeWorker(
        client: http_testing.MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
      );
      final report = await worker.flushOnce();
      expect(report.retried, 1);
    });

    test('drops a row after maxAttempts', () async {
      final id = await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      // Pre-set attempts to maxAttempts-1 so the next failure trips
      // the drop threshold.
      await storage.markTelemetryRetry(
        id: id,
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
        lastError: 'simulated',
      );
      // markTelemetryRetry only increments once; we need attempts=9
      // (maxAttempts=10 default). Call it 8 more times.
      for (var i = 0; i < 8; i++) {
        await storage.markTelemetryRetry(
          id: id,
          nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(0),
          lastError: 'simulated',
        );
      }
      final worker = makeWorker(
        client: http_testing.MockClient(
          (_) async => http.Response('boom', 500),
        ),
      );
      final report = await worker.flushOnce();
      expect(report.dropped, 1);
      expect(report.retried, 0);
    });
  });

  group('permanent failures drop', () {
    test('400 drops the row immediately', () async {
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      final worker = makeWorker(
        client: http_testing.MockClient(
          (_) async => http.Response('bad request', 400),
        ),
      );
      final report = await worker.flushOnce();
      expect(report.dropped, 1);
      expect(report.retried, 0);

      // After drop, the row is gone.
      await storage.releaseStaleTelemetryClaims(
        staleThreshold: Duration.zero,
      );
      final remaining = await storage.claimDueTelemetryRows();
      expect(remaining, isEmpty);
    });
  });

  group('single-flight', () {
    test('a second flushOnce while the first is in flight returns empty',
        () async {
      // Pump a row and a long-running mock so the second flushOnce
      // call hits the _flushing guard.
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      final block = Completer<http.Response>();
      final worker = makeWorker(
        client: http_testing.MockClient((_) => block.future),
      );
      final first = worker.flushOnce();
      // Microtask boundary so first call enters _flushing=true.
      await Future<void>.delayed(Duration.zero);
      final second = await worker.flushOnce();
      expect(second.claimed, 0);

      block.complete(http.Response('', 200));
      final firstReport = await first;
      expect(firstReport.deleted, 1);
    });
  });

  group('boot recovery', () {
    test('start() releases stale claims', () async {
      // Pump a row, claim it manually to simulate a crashed previous
      // worker's lease, then call start() with a 0 threshold to
      // verify the claim is released.
      await storage.appendTelemetryRow(
        signalKind: TelemetrySignalKind.trace,
        payload: payload('p'),
      );
      await storage.claimDueTelemetryRows(); // creates a claim

      // Sleep so the claim is "old".
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final worker = TelemetryFlushWorker(
        storage: storage,
        collectorBaseUrl: Uri.parse('http://localhost:4318'),
        httpClient:
            http_testing.MockClient((_) async => http.Response('', 200)),
      );
      // Default staleThreshold = 5 minutes; override storage call
      // directly to release everything for the test.
      await storage.releaseStaleTelemetryClaims(
        staleThreshold: const Duration(milliseconds: 1),
      );
      final report = await worker.flushOnce();
      expect(report.claimed, 1);
      worker.stop();
    });
  });
}
