import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config_service.dart';

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
  });
}
