import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/features/recording/data/groq_stt_service.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';

// ---------------------------------------------------------------------------
// Fake HTTP adapter — no real network calls
// ---------------------------------------------------------------------------

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(String body, {int statusCode = 200}) {
  final bytes = utf8.encode(body);
  return ResponseBody.fromBytes(
    bytes,
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    },
  );
}

// ---------------------------------------------------------------------------
// Provider + Helpers
// ---------------------------------------------------------------------------

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);

  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<void> saveGroqApiKey(String key) async {}

  @override
  Future<void> saveApiUrl(String url) async {}

  @override
  Future<void> saveApiToken(String token) async {}
}

/// A provider that builds a [GroqSttService] with an injected [Dio].
/// Using `.family` so each test can inject its own fake Dio.
final _groqSvcProvider =
    Provider.family<GroqSttService, Dio>((ref, dio) => GroqSttService(ref, dio: dio));

/// Creates a [ProviderContainer] pre-loaded with [config].
ProviderContainer _container(AppConfig config) {
  return ProviderContainer(
    overrides: [
      appConfigServiceProvider.overrideWithValue(_FixedConfigService(config)),
    ],
  );
}

/// Returns a [GroqSttService] that uses [container]'s config and a fake HTTP [handler].
/// Awaits [AppConfigNotifier.loadCompleted] so the config is fully loaded before use.
Future<GroqSttService> _service(
  ProviderContainer container,
  Future<ResponseBody> Function(RequestOptions) handler,
) async {
  await container.read(appConfigProvider.notifier).loadCompleted;
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter(handler);
  return container.read(_groqSvcProvider(dio));
}

/// Writes a minimal WAV placeholder so the service doesn't throw a filesystem error.
Future<String> _tempWavPath() async {
  final file = await File('${Directory.systemTemp.path}/test_audio.wav')
      .create(recursive: true);
  await file.writeAsBytes(List.filled(44, 0));
  return file.path;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('GroqSttService', () {
    test('200 success — maps all TranscriptResult fields correctly', () async {
      const responseJson = '''
{
  "text": "Hello world",
  "language": "en",
  "duration": 3.5,
  "segments": [
    {"text": " Hello", "start": 0.0, "end": 1.5},
    {"text": " world", "start": 1.5, "end": 3.5}
  ]
}''';

      final container = _container(
        const AppConfig(groqApiKey: 'gsk_test', language: 'auto'),
      );
      final svc = await _service(
        container,
        (_) async => _jsonResponse(responseJson),
      );

      final path = await _tempWavPath();
      final result = await svc.transcribe(path);

      expect(result.text, 'Hello world');
      expect(result.detectedLanguage, 'en');
      expect(result.audioDurationMs, 3500);
      expect(result.segments, hasLength(2));
      expect(result.segments.first.text, 'Hello');
      expect(result.segments.first.startMs, 0);
      expect(result.segments.first.endMs, 1500);
      expect(result.segments.last.text, 'world');
      expect(result.segments.last.endMs, 3500);
    });

    test('missing groq key → SttException("Groq API key not configured")', () async {
      final container = _container(const AppConfig(groqApiKey: null));
      final svc = await _service(container, (_) async => throw AssertionError('should not be called'));

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(
          isA<SttException>().having(
            (e) => e.message,
            'message',
            'Groq API key not configured',
          ),
        ),
      );
    });

    test('empty groq key → SttException("Groq API key not configured")', () async {
      final container = _container(const AppConfig(groqApiKey: ''));
      final svc = await _service(container, (_) async => throw AssertionError('should not be called'));

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Groq API key not configured',
        )),
      );
    });

    test('401 → SttException("Invalid Groq API key")', () async {
      final container = _container(const AppConfig(groqApiKey: 'gsk_bad'));
      final svc = await _service(
        container,
        (_) async => _jsonResponse('{"error":{"message":"Unauthorized"}}', statusCode: 401),
      );

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Invalid Groq API key',
        )),
      );
    });

    test('429 → SttException("Groq rate limit exceeded")', () async {
      final container = _container(const AppConfig(groqApiKey: 'gsk_test'));
      final svc = await _service(
        container,
        (_) async => _jsonResponse('{"error":{"message":"Rate limit"}}', statusCode: 429),
      );

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Groq rate limit exceeded',
        )),
      );
    });

    test('500 → SttException("Groq service unavailable")', () async {
      final container = _container(const AppConfig(groqApiKey: 'gsk_test'));
      final svc = await _service(
        container,
        (_) async => _jsonResponse('{"error":{"message":"Internal error"}}', statusCode: 500),
      );

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Groq service unavailable',
        )),
      );
    });

    test('4xx with missing error body → falls back to "Transcription failed"', () async {
      final container = _container(const AppConfig(groqApiKey: 'gsk_test'));
      final svc = await _service(
        container,
        (_) async => _jsonResponse('{}', statusCode: 422),
      );

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Transcription failed',
        )),
      );
    });

    test('sendTimeout → SttException("Groq service unavailable")', () async {
      final container = _container(const AppConfig(groqApiKey: 'gsk_test'));
      final svc = await _service(container, (opts) async {
        throw DioException(
          requestOptions: opts,
          type: DioExceptionType.sendTimeout,
        );
      });

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Groq service unavailable',
        )),
      );
    });

    test('receiveTimeout → SttException("Groq service unavailable")', () async {
      final container = _container(const AppConfig(groqApiKey: 'gsk_test'));
      final svc = await _service(container, (opts) async {
        throw DioException(
          requestOptions: opts,
          type: DioExceptionType.receiveTimeout,
        );
      });

      final path = await _tempWavPath();
      expect(
        () => svc.transcribe(path),
        throwsA(isA<SttException>().having(
          (e) => e.message,
          'message',
          'Groq service unavailable',
        )),
      );
    });

    test('language != auto → language param is included in request', () async {
      String? capturedLanguage;
      const responseJson =
          '{"text":"Cześć","language":"pl","duration":1.0,"segments":[]}';

      final container = _container(
        const AppConfig(groqApiKey: 'gsk_test', language: 'pl'),
      );
      final svc = await _service(container, (opts) async {
        final data = opts.data;
        if (data is FormData) {
          for (final field in data.fields) {
            if (field.key == 'language') capturedLanguage = field.value;
          }
        }
        return _jsonResponse(responseJson);
      });

      final path = await _tempWavPath();
      await svc.transcribe(path);

      expect(capturedLanguage, 'pl');
    });

    test('language == auto → language param is omitted from request', () async {
      bool languagePresent = false;
      const responseJson =
          '{"text":"Hello","language":"en","duration":1.0,"segments":[]}';

      final container = _container(
        const AppConfig(groqApiKey: 'gsk_test', language: 'auto'),
      );
      final svc = await _service(container, (opts) async {
        final data = opts.data;
        if (data is FormData) {
          languagePresent = data.fields.any((f) => f.key == 'language');
        }
        return _jsonResponse(responseJson);
      });

      final path = await _tempWavPath();
      await svc.transcribe(path);

      expect(languagePresent, isFalse);
    });

    test('isModelLoaded always returns true', () async {
      final container = _container(const AppConfig());
      final svc = await _service(container, (_) async => throw AssertionError('no http'));
      expect(await svc.isModelLoaded(), isTrue);
    });

    test('loadModel is a no-op', () async {
      final container = _container(const AppConfig());
      final svc = await _service(container, (_) async => throw AssertionError('no http'));
      await expectLater(svc.loadModel(), completes);
    });
  });
}
