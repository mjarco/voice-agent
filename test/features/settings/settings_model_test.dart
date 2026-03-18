import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/settings/settings_model.dart';

void main() {
  group('AppSettings', () {
    test('defaults are correct', () {
      const settings = AppSettings();
      expect(settings.apiUrl, isNull);
      expect(settings.apiToken, isNull);
      expect(settings.autoSend, isTrue);
      expect(settings.language, 'auto');
      expect(settings.keepHistory, isTrue);
    });

    test('copyWith updates specified fields', () {
      const original = AppSettings();
      final updated = original.copyWith(
        apiUrl: 'https://example.com',
        autoSend: false,
      );

      expect(updated.apiUrl, 'https://example.com');
      expect(updated.autoSend, isFalse);
      expect(updated.language, 'auto'); // unchanged
      expect(updated.keepHistory, isTrue); // unchanged
    });

    test('copyWith preserves original when no args', () {
      const original = AppSettings(
        apiUrl: 'https://test.com',
        autoSend: false,
        language: 'pl',
      );
      final copy = original.copyWith();

      expect(copy.apiUrl, 'https://test.com');
      expect(copy.autoSend, isFalse);
      expect(copy.language, 'pl');
    });
  });
}
