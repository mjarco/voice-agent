import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';

void main() {

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

    group('P026 removal migration', () {
      test('fresh install → migration runs, flag set, no errors', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.load();

        expect(prefs.getBool('wake_word_removal_migration_done'), isTrue);
      });

      test('full state → all retired keys removed', () async {
        SharedPreferences.setMockInitialValues({
          'background_listening_enabled': true,
          'wake_word_enabled': true,
          'wake_word_keyword': 'alexa',
          'wake_word_sensitivity': 0.8,
          'activation_state': 'listening',
          'activation_toggle_requested': true,
          'activation_stop_requested': false,
          'foreground_service_running': true,
        });
        FlutterSecureStorage.setMockInitialValues(
            {'picovoice_access_key': 'pv_test'});
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.load();

        expect(prefs.containsKey('background_listening_enabled'), isFalse);
        expect(prefs.containsKey('wake_word_enabled'), isFalse);
        expect(prefs.containsKey('wake_word_keyword'), isFalse);
        expect(prefs.containsKey('wake_word_sensitivity'), isFalse);
        expect(prefs.containsKey('activation_state'), isFalse);
        expect(prefs.containsKey('activation_toggle_requested'), isFalse);
        expect(prefs.containsKey('activation_stop_requested'), isFalse);
        expect(prefs.containsKey('foreground_service_running'), isFalse);
        expect(prefs.getBool('wake_word_removal_migration_done'), isTrue);
      });

      test('already migrated (flag = true) → retired keys NOT re-touched',
          () async {
        // Simulate a fresh install that's somehow already past the migration
        // AND has a leftover key (shouldn't happen in practice, but verifies
        // the gate is honored).
        SharedPreferences.setMockInitialValues({
          'wake_word_removal_migration_done': true,
          'background_listening_enabled': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.load();

        // Flag was set — migration should have been skipped, leaving the
        // leftover value untouched.
        expect(prefs.getBool('background_listening_enabled'), isTrue);
      });

      test('idempotent across two load() calls', () async {
        SharedPreferences.setMockInitialValues({
          'background_listening_enabled': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        await service.load();
        await service.load();

        expect(prefs.getBool('wake_word_removal_migration_done'), isTrue);
        expect(prefs.containsKey('background_listening_enabled'), isFalse);
      });

      test(
          'load does NOT expose removed fields — config only has migrated-only keys',
          () async {
        SharedPreferences.setMockInitialValues({
          'background_listening_enabled': true,
          'wake_word_keyword': 'alexa',
        });
        final prefs = await SharedPreferences.getInstance();
        final service = AppConfigService(prefs: prefs);

        final config = await service.load();

        // AppConfig no longer has those fields at compile time; this test
        // asserts that the surviving config has the standard (unrelated)
        // fields intact after migration.
        expect(config.apiUrl, isNull);
        expect(config.vadConfig, const VadConfig.defaults());
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
