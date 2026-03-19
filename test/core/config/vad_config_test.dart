import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/config/vad_config.dart';

void main() {
  group('VadConfig.defaults()', () {
    test('has expected default values', () {
      const d = VadConfig.defaults();
      expect(d.positiveSpeechThreshold, 0.40);
      expect(d.negativeSpeechThreshold, 0.35);
      expect(d.hangoverMs, 500);
      expect(d.minSpeechMs, 400);
      expect(d.preRollMs, 300);
    });
  });

  group('VadConfig.copyWith()', () {
    test('returns same values when no overrides', () {
      const original = VadConfig.defaults();
      final copy = original.copyWith();
      expect(copy, original);
    });

    test('overrides only specified fields', () {
      const original = VadConfig.defaults();
      final copy = original.copyWith(hangoverMs: 1000, preRollMs: 200);
      expect(copy.hangoverMs, 1000);
      expect(copy.preRollMs, 200);
      expect(copy.positiveSpeechThreshold, original.positiveSpeechThreshold);
      expect(copy.negativeSpeechThreshold, original.negativeSpeechThreshold);
      expect(copy.minSpeechMs, original.minSpeechMs);
    });
  });

  group('VadConfig.clamp()', () {
    test('values within range are unchanged', () {
      const c = VadConfig.defaults();
      expect(c.clamp(), c);
    });

    test('positiveSpeechThreshold clamped below minimum', () {
      final c = const VadConfig.defaults()
          .copyWith(positiveSpeechThreshold: 0.0)
          .clamp();
      expect(c.positiveSpeechThreshold, 0.1);
    });

    test('positiveSpeechThreshold clamped above maximum', () {
      final c = const VadConfig.defaults()
          .copyWith(positiveSpeechThreshold: 1.5)
          .clamp();
      expect(c.positiveSpeechThreshold, 0.9);
    });

    test('negativeSpeechThreshold clamped above maximum', () {
      final c = const VadConfig.defaults()
          .copyWith(negativeSpeechThreshold: 0.99)
          .clamp();
      expect(c.negativeSpeechThreshold, 0.8);
    });

    test('hangoverMs clamped below minimum', () {
      final c =
          const VadConfig.defaults().copyWith(hangoverMs: 0).clamp();
      expect(c.hangoverMs, 100);
    });

    test('hangoverMs clamped above maximum', () {
      final c =
          const VadConfig.defaults().copyWith(hangoverMs: 9999).clamp();
      expect(c.hangoverMs, 2000);
    });

    test('minSpeechMs clamped above maximum', () {
      final c =
          const VadConfig.defaults().copyWith(minSpeechMs: 5000).clamp();
      expect(c.minSpeechMs, 1000);
    });

    test('preRollMs clamped above maximum', () {
      final c =
          const VadConfig.defaults().copyWith(preRollMs: 9999).clamp();
      expect(c.preRollMs, 800);
    });

    test('all fields out-of-range are clamped simultaneously', () {
      final c = const VadConfig(
        positiveSpeechThreshold: -1,
        negativeSpeechThreshold: 99,
        hangoverMs: -500,
        minSpeechMs: 99999,
        preRollMs: 0,
      ).clamp();
      expect(c.positiveSpeechThreshold, 0.1);
      expect(c.negativeSpeechThreshold, 0.8);
      expect(c.hangoverMs, 100);
      expect(c.minSpeechMs, 1000);
      expect(c.preRollMs, 100);
    });
  });

  group('VadConfig equality', () {
    test('two defaults are equal', () {
      expect(const VadConfig.defaults(), const VadConfig.defaults());
    });

    test('different values are not equal', () {
      const a = VadConfig.defaults();
      final b = a.copyWith(hangoverMs: 1000);
      expect(a, isNot(b));
    });

    test('hashCode matches for equal configs', () {
      expect(
        const VadConfig.defaults().hashCode,
        const VadConfig.defaults().hashCode,
      );
    });
  });

  group('VadConfig.toString()', () {
    test('contains field values', () {
      final s = const VadConfig.defaults().toString();
      expect(s, contains('0.4'));
      expect(s, contains('500'));
      expect(s, contains('400'));
      expect(s, contains('300'));
    });
  });
}
