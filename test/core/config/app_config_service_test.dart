import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';

void main() {
  group('AppConfig.copyWith', () {
    test('picovoiceAccessKey sentinel allows setting to null', () {
      const config = AppConfig(picovoiceAccessKey: 'key');
      final updated = config.copyWith(picovoiceAccessKey: null);
      expect(updated.picovoiceAccessKey, isNull);
    });

    test('picovoiceAccessKey omitted preserves value', () {
      const config = AppConfig(picovoiceAccessKey: 'key');
      final updated = config.copyWith(backgroundListeningEnabled: true);
      expect(updated.picovoiceAccessKey, 'key');
    });

    test('new fields have correct defaults', () {
      const config = AppConfig();
      expect(config.backgroundListeningEnabled, isFalse);
      expect(config.wakeWordEnabled, isFalse);
      expect(config.picovoiceAccessKey, isNull);
      expect(config.wakeWordKeyword, 'jarvis');
      expect(config.wakeWordSensitivity, 0.5);
    });

    test('copyWith updates new fields', () {
      const config = AppConfig();
      final updated = config.copyWith(
        backgroundListeningEnabled: true,
        wakeWordEnabled: true,
        picovoiceAccessKey: 'pv_key',
        wakeWordKeyword: 'computer',
        wakeWordSensitivity: 0.8,
      );
      expect(updated.backgroundListeningEnabled, isTrue);
      expect(updated.wakeWordEnabled, isTrue);
      expect(updated.picovoiceAccessKey, 'pv_key');
      expect(updated.wakeWordKeyword, 'computer');
      expect(updated.wakeWordSensitivity, 0.8);
    });
  });

  group('AppConfigService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('load returns defaults when storage is empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      final config = await service.load();

      expect(config.apiUrl, isNull);
      expect(config.apiToken, isNull);
      expect(config.groqApiKey, isNull);
      expect(config.autoSend, isTrue);
      expect(config.language, 'auto');
      expect(config.keepHistory, isTrue);
    });

    test('saveApiUrl then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveApiUrl('https://example.com/api');
      final config = await service.load();

      expect(config.apiUrl, 'https://example.com/api');
    });

    test('saveAutoSend then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveAutoSend(false);
      final config = await service.load();

      expect(config.autoSend, isFalse);
    });

    test('saveLanguage then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveLanguage('pl');
      final config = await service.load();

      expect(config.language, 'pl');
    });

    test('saveKeepHistory then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveKeepHistory(false);
      final config = await service.load();

      expect(config.keepHistory, isFalse);
    });

    test('saveGroqApiKey then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveGroqApiKey('gsk_test_key');
      final config = await service.load();

      expect(config.groqApiKey, 'gsk_test_key');
    });

    test('saveGroqApiKey with empty string stores empty string', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveGroqApiKey('gsk_test_key');
      await service.saveGroqApiKey('');
      final config = await service.load();

      expect(config.groqApiKey, '');
    });

    test('multiple saves preserve all values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveApiUrl('https://test.com');
      await service.saveAutoSend(false);
      await service.saveLanguage('en');
      await service.saveKeepHistory(false);

      final config = await service.load();

      expect(config.apiUrl, 'https://test.com');
      expect(config.autoSend, isFalse);
      expect(config.language, 'en');
      expect(config.keepHistory, isFalse);
    });

    test('saveAudioFeedbackEnabled then load round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = AppConfigService(prefs: prefs);

      await service.saveAudioFeedbackEnabled(false);
      final config = await service.load();

      expect(config.audioFeedbackEnabled, isFalse);
    });

    group('background activation config', () {
      test('load returns defaults for new fields when storage is empty',
          () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        final config = await service.load();

        expect(config.backgroundListeningEnabled, isFalse);
        expect(config.wakeWordEnabled, isFalse);
        expect(config.picovoiceAccessKey, isNull);
        expect(config.wakeWordKeyword, 'jarvis');
        expect(config.wakeWordSensitivity, 0.5);
      });

      test('saveBackgroundListeningEnabled then load round-trips', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.saveBackgroundListeningEnabled(true);
        final config = await service.load();

        expect(config.backgroundListeningEnabled, isTrue);
      });

      test('saveWakeWordEnabled then load round-trips', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.saveWakeWordEnabled(true);
        final config = await service.load();

        expect(config.wakeWordEnabled, isTrue);
      });

      test('savePicovoiceAccessKey then load round-trips', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.savePicovoiceAccessKey('pv_test_key_12345');
        final config = await service.load();

        expect(config.picovoiceAccessKey, 'pv_test_key_12345');
      });

      test('saveWakeWordKeyword then load round-trips', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.saveWakeWordKeyword('computer');
        final config = await service.load();

        expect(config.wakeWordKeyword, 'computer');
      });

      test('saveWakeWordSensitivity then load round-trips', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.saveWakeWordSensitivity(0.8);
        final config = await service.load();

        expect(config.wakeWordSensitivity, 0.8);
      });

      test('picovoiceAccessKey survives SecureStorage failure gracefully',
          () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        // Use a fresh service — FlutterSecureStorage mock has no key stored,
        // so read returns null (simulating empty/failed storage)
        final service = AppConfigService(prefs: prefs);

        final config = await service.load();

        expect(config.picovoiceAccessKey, isNull);
      });

      test('all background activation fields preserved alongside other config',
          () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.saveApiUrl('https://test.com');
        await service.saveBackgroundListeningEnabled(true);
        await service.saveWakeWordEnabled(true);
        await service.savePicovoiceAccessKey('pv_key');
        await service.saveWakeWordKeyword('alexa');
        await service.saveWakeWordSensitivity(0.7);
        final config = await service.load();

        expect(config.apiUrl, 'https://test.com');
        expect(config.backgroundListeningEnabled, isTrue);
        expect(config.wakeWordEnabled, isTrue);
        expect(config.picovoiceAccessKey, 'pv_key');
        expect(config.wakeWordKeyword, 'alexa');
        expect(config.wakeWordSensitivity, 0.7);
      });
    });

    group('VAD config', () {
      test('load returns VadConfig.defaults() when keys are absent', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        final config = await service.load();

        expect(config.vadConfig, const VadConfig.defaults());
      });

      test('saveVadConfig then load round-trips all 5 fields', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        const saved = VadConfig(
          positiveSpeechThreshold: 0.6,
          negativeSpeechThreshold: 0.5,
          hangoverMs: 800,
          minSpeechMs: 600,
          preRollMs: 400,
        );
        await service.saveVadConfig(saved);
        final config = await service.load();

        expect(config.vadConfig, saved);
      });

      test('load clamps out-of-range values from SharedPreferences', () async {
        SharedPreferences.setMockInitialValues({
          'vad_positive_threshold': 2.0,
          'vad_negative_threshold': -1.0,
          'vad_hangover_ms': 99999,
          'vad_min_speech_ms': -50,
          'vad_pre_roll_ms': 50,
        });
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        final config = await service.load();

        expect(config.vadConfig.positiveSpeechThreshold, 0.9);
        expect(config.vadConfig.negativeSpeechThreshold, 0.1);
        expect(config.vadConfig.hangoverMs, 2000);
        expect(config.vadConfig.minSpeechMs, 100);
        expect(config.vadConfig.preRollMs, 100);
      });

      test('saveVadConfig preserves other config fields', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.saveApiUrl('https://test.com');
        await service.saveVadConfig(
          const VadConfig.defaults().copyWith(hangoverMs: 1200),
        );
        final config = await service.load();

        expect(config.apiUrl, 'https://test.com');
        expect(config.vadConfig.hangoverMs, 1200);
      });
    });
  });
}
