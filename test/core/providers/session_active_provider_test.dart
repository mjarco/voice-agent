import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';

void main() {
  group('sessionActiveProvider', () {
    test('default is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(sessionActiveProvider), isFalse);
    });

    test('can be written to true and read back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(sessionActiveProvider.notifier).state = true;
      expect(container.read(sessionActiveProvider), isTrue);
    });

    test('can flip false → true → false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(sessionActiveProvider.notifier).state = true;
      expect(container.read(sessionActiveProvider), isTrue);

      container.read(sessionActiveProvider.notifier).state = false;
      expect(container.read(sessionActiveProvider), isFalse);
    });
  });
}
