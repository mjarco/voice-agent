// P039 T6 — STT telemetry. Asserts the Groq HTTP round-trip is wrapped
// in a `stt.request` span with the expected attributes on both the
// happy path and the DioException path.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/features/recording/data/groq_stt_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions) _handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? rs,
          Future<void>? cf) =>
      _handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(String body, {int status = 200}) {
  return ResponseBody.fromBytes(
    utf8.encode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    },
  );
}

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._cfg);
  final AppConfig _cfg;
  @override
  Future<AppConfig> load() async => _cfg;
}

Future<String> _tempWavPath(String name) async {
  final file = await File('${Directory.systemTemp.path}/$name.wav')
      .create(recursive: true);
  await file.writeAsBytes(List.filled(44, 0));
  return file.path;
}

void main() {
  late _Recording recording;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    recording = _Recording();
    Telemetry.instance = recording;
  });

  tearDown(() {
    Telemetry.instance = const NoopTelemetry();
  });

  Future<GroqSttService> svc({
    required AppConfig config,
    required Future<ResponseBody> Function(RequestOptions) handler,
  }) async {
    final container = ProviderContainer(overrides: [
      appConfigServiceProvider.overrideWithValue(_FixedConfigService(config)),
    ]);
    await container.read(appConfigProvider.notifier).loadCompleted;
    final dio = Dio()..httpClientAdapter = _FakeAdapter(handler);
    final p = Provider.family<GroqSttService, Dio>((ref, d) =>
        GroqSttService(ref, dio: d));
    return container.read(p(dio));
  }

  test('happy-path emits stt.request span with audio_duration_ms', () async {
    const body = '''
{"text":"hi","language":"en","duration":2.0,"segments":[]}''';
    final s = await svc(
      config: const AppConfig(groqApiKey: 'gsk_test'),
      handler: (_) async => _jsonResponse(body),
    );
    await s.transcribe(await _tempWavPath('happy'));

    expect(recording.spans, hasLength(1));
    final span = recording.spans.single;
    expect(span.name, 'stt.request');
    expect(span.attrs['stt.provider'], 'groq');
    expect(span.attrs['stt.model'], 'whisper-large-v3-turbo');
    expect(span.attrEvents['stt.audio_duration_ms'], 2000);
    expect(span.attrEvents['stt.detected_language'], 'en');
    expect(span.attrEvents['stt.segment_count'], 0);
    expect(span.attrEvents['http.status_code'], 200);
    expect(span.endedStatus, SpanStatus.ok);
  });

  test('http 401 marks span as error with http.status_code', () async {
    final s = await svc(
      config: const AppConfig(groqApiKey: 'gsk_test'),
      handler: (_) async => _jsonResponse('{}', status: 401),
    );
    final path = await _tempWavPath('err');
    await expectLater(
      () => s.transcribe(path),
      throwsA(isA<Exception>()),
    );

    expect(recording.spans, hasLength(1));
    final span = recording.spans.single;
    expect(span.name, 'stt.request');
    expect(span.attrEvents['http.status_code'], 401);
    expect(span.endedStatus, SpanStatus.error);
  });
}

// ── Test-only Recording Telemetry ────────────────────────────────────────────

class _Recording implements Telemetry {
  final List<_RecSpan> spans = [];

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {}

  @override
  TelemetrySpan span(String name,
      {SpanKind kind = SpanKind.internal,
      Map<String, Object?> attrs = const {}}) {
    final s = _RecSpan(name, Map<String, Object?>.from(attrs));
    spans.add(s);
    return s;
  }

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {}

  @override
  void histogram(String name, num value,
      {Map<String, Object?> attrs = const {}}) {}

  @override
  Future<void> flush() async {}
}

class _RecSpan implements TelemetrySpan {
  _RecSpan(this.name, this.attrs);
  final String name;
  final Map<String, Object?> attrs; // attrs set at start()
  final Map<String, Object?> attrEvents = {}; // attrs added via setAttr
  SpanStatus? endedStatus;
  String? endedMessage;

  @override
  void setAttr(String key, Object? value) {
    if (endedStatus != null) return;
    attrEvents[key] = value;
  }

  @override
  void addEvent(String name, {Map<String, Object?> attrs = const {}}) {}

  @override
  void end({SpanStatus status = SpanStatus.unset, String? message}) {
    if (endedStatus != null) return;
    endedStatus = status;
    endedMessage = message;
  }
}
