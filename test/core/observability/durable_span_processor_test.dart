// P039 T4b — DurableSpanProcessor + OtlpEncoder integration.
//
// Persist-on-end through real sqflite_common_ffi storage; assert the
// encoded payload round-trips back to a parseable OTLP/JSON envelope
// with the expected fields.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/observability/durable_span_processor.dart';
import 'package:voice_agent/core/observability/telemetry_outbox_row.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

void main() {
  late SqliteStorageService storage;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('dsp_test_');
    storage = await SqliteStorageService.initialize(
      databaseFactory: databaseFactoryFfi,
      path: '${tempDir.path}/dsp.db',
    );
  });

  otel_sdk.TracerProviderBase makeProvider(otel_sdk.SpanProcessor processor) {
    return otel_sdk.TracerProviderBase(
      processors: [processor],
      resource: otel_sdk.Resource([
        otel_api.Attribute.fromString('service.name', 'voice-agent-test'),
        otel_api.Attribute.fromString('deployment.environment', 'dev'),
      ]),
    );
  }

  test('onEnd persists exactly one outbox row per ended span', () async {
    final processor = DurableSpanProcessor(storage: storage);
    final provider = makeProvider(processor);
    final tracer = provider.getTracer('test-scope');

    tracer.startSpan('hf.attach_stream').end();
    tracer.startSpan('hf.gate_changed').end();

    await processor.drain();

    final claimed = await storage.claimDueTelemetryRows();
    expect(claimed, hasLength(2));
  });

  test('persisted payload is valid OTLP/JSON with expected fields',
      () async {
    final processor = DurableSpanProcessor(storage: storage);
    final provider = makeProvider(processor);
    final tracer = provider.getTracer('test-scope');

    final span = tracer.startSpan(
      'hf.stream_error',
      attributes: [
        otel_api.Attribute.fromString('message', 'avfaudio 2003329396'),
        otel_api.Attribute.fromBoolean('requires_settings', false),
        otel_api.Attribute.fromInt('attempts', 3),
      ],
    );
    span.addEvent('chunk_received',
        attributes: [otel_api.Attribute.fromBoolean('gate_open', true)]);
    span.end();

    await processor.drain();

    final rows = await storage.claimDueTelemetryRows();
    expect(rows, hasLength(1));
    final decoded = jsonDecode(utf8.decode(rows.single.payload))
        as Map<String, dynamic>;

    expect(decoded['resourceSpans'], isA<List>());
    final resourceSpan =
        (decoded['resourceSpans'] as List).single as Map<String, dynamic>;

    // Resource attributes carry from the provider.
    final resourceAttrs = resourceSpan['resource']['attributes']
        as List<dynamic>;
    final attrMap = {
      for (final a in resourceAttrs.cast<Map<String, dynamic>>())
        a['key'] as String:
            ((a['value'] as Map<String, dynamic>)['stringValue']) as String?,
    };
    expect(attrMap['service.name'], 'voice-agent-test');
    expect(attrMap['deployment.environment'], 'dev');

    // Span body.
    final scopeSpan =
        (resourceSpan['scopeSpans'] as List).single as Map<String, dynamic>;
    expect(scopeSpan['scope']['name'], 'test-scope');
    final spanJson =
        (scopeSpan['spans'] as List).single as Map<String, dynamic>;
    expect(spanJson['name'], 'hf.stream_error');
    expect(spanJson['kind'], 1); // INTERNAL
    expect(spanJson['traceId'], isA<String>());
    expect((spanJson['traceId'] as String).length, 32);
    expect((spanJson['spanId'] as String).length, 16);

    // Span attributes.
    final spanAttrs = (spanJson['attributes'] as List)
        .cast<Map<String, dynamic>>();
    final byKey = {for (final a in spanAttrs) a['key'] as String: a['value']};
    expect((byKey['message'] as Map)['stringValue'],
        'avfaudio 2003329396');
    expect((byKey['requires_settings'] as Map)['boolValue'], false);
    // intValue is stringified per OTel spec.
    expect((byKey['attempts'] as Map)['intValue'], '3');

    // Event with its own attributes.
    final events =
        (spanJson['events'] as List).cast<Map<String, dynamic>>();
    expect(events, hasLength(1));
    expect(events.single['name'], 'chunk_received');
    final evAttrs = (events.single['attributes'] as List)
        .cast<Map<String, dynamic>>();
    expect((evAttrs.single['value'] as Map)['boolValue'], true);
  });

  test('persist errors flow through the onPersistError hook', () async {
    final errors = <Object>[];
    final brokenStorage = _BrokenStorage();
    final processor = DurableSpanProcessor(
      storage: brokenStorage,
      onPersistError: (e, st) => errors.add(e),
    );
    final tracer = makeProvider(processor).getTracer('test');

    tracer.startSpan('boom').end();
    await processor.drain();

    expect(errors, hasLength(1));
    expect(errors.single.toString(), contains('intentional'));
  });

  test('drain awaits all in-flight persists', () async {
    final processor = DurableSpanProcessor(storage: storage);
    final tracer = makeProvider(processor).getTracer('test');

    for (var i = 0; i < 50; i++) {
      tracer.startSpan('span-$i').end();
    }
    // Before drain, rows may not all be on disk yet (microtasks pending).
    await processor.drain();
    final rows = await storage.claimDueTelemetryRows(limit: 100);
    expect(rows, hasLength(50));
  });
}

class _BrokenStorage with TelemetryStorageNoop implements StorageService {
  @override
  Future<int> appendTelemetryRow({
    required TelemetrySignalKind signalKind,
    required Uint8List payload,
  }) async {
    throw StateError('intentional persist failure');
  }

  // Unused StorageService methods — no-op stubs.
  @override
  Future<String> getDeviceId() async => 'test';
  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
          {int limit = 20, int offset = 0}) async =>
      const [];
  @override
  Future<void> saveTranscript(Transcript t) async {}
  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts(
          {int limit = 50, int offset = 0}) async =>
      const [];
  @override
  Future<void> deleteTranscript(String id) async {}
  @override
  Future<void> enqueue(String transcriptId) async {}
  @override
  Future<List<SyncQueueItem>> getPendingItems() async => const [];
  @override
  Future<void> markSending(String id) async {}
  @override
  Future<void> markSent(String id) async {}
  @override
  Future<void> markFailed(String id, String error,
      {int? overrideAttempts}) async {}
  @override
  Future<void> markPendingForRetry(String id) async {}
  @override
  Future<void> reactivateForResend(String transcriptId) async {}
  @override
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async =>
      const [];
}
