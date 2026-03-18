import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('defaults are correct', () {
      const config = AppConfig();
      expect(config.apiUrl, isNull);
      expect(config.apiToken, isNull);
      expect(config.groqApiKey, isNull);
      expect(config.autoSend, isTrue);
      expect(config.language, 'auto');
      expect(config.keepHistory, isTrue);
    });

    test('copyWith updates specified fields', () {
      const original = AppConfig();
      final updated = original.copyWith(
        apiUrl: 'https://example.com',
        autoSend: false,
      );

      expect(updated.apiUrl, 'https://example.com');
      expect(updated.autoSend, isFalse);
      expect(updated.language, 'auto');
      expect(updated.keepHistory, isTrue);
    });

    test('copyWith preserves original when no args', () {
      const original = AppConfig(
        apiUrl: 'https://test.com',
        autoSend: false,
        language: 'pl',
      );
      final copy = original.copyWith();

      expect(copy.apiUrl, 'https://test.com');
      expect(copy.autoSend, isFalse);
      expect(copy.language, 'pl');
    });

    test('copyWith updates groqApiKey', () {
      const original = AppConfig();
      final updated = original.copyWith(groqApiKey: 'gsk_test');
      expect(updated.groqApiKey, 'gsk_test');
    });

    test('copyWith(groqApiKey: null) clears the key', () {
      const original = AppConfig(groqApiKey: 'gsk_test');
      final updated = original.copyWith(groqApiKey: null);
      expect(updated.groqApiKey, isNull);
    });

    test('copyWith without groqApiKey preserves existing value', () {
      const original = AppConfig(groqApiKey: 'gsk_test');
      final updated = original.copyWith(autoSend: false);
      expect(updated.groqApiKey, 'gsk_test');
    });
  });
}
