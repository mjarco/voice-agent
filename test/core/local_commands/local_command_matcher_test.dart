import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/local_commands/local_command_matcher.dart';

void main() {
  const matcher = LocalCommandMatcher();

  group('LocalCommandMatcher — replayLast whitelist', () {
    const whitelist = [
      'powtórz',
      'powtórz proszę',
      'powtórz to',
      'powtórz jeszcze raz',
      'jeszcze raz',
      'repeat',
      'say again',
      'say it again',
    ];

    for (final entry in whitelist) {
      test('exact "$entry" → replayLast', () {
        expect(matcher.match(entry), isA<LocalCommandReplayLast>());
      });

      test('uppercased "$entry" → replayLast', () {
        expect(
          matcher.match(entry.toUpperCase()),
          isA<LocalCommandReplayLast>(),
        );
      });

      test('trailing punctuation "$entry." → replayLast', () {
        expect(matcher.match('$entry.'), isA<LocalCommandReplayLast>());
      });

      test('surrounding whitespace " $entry " → replayLast', () {
        expect(matcher.match('  $entry  '), isA<LocalCommandReplayLast>());
      });
    }

    test('mixed punctuation "Powtórz!?" → replayLast', () {
      expect(matcher.match('Powtórz!?'), isA<LocalCommandReplayLast>());
    });

    test('internal whitespace collapse "say  again" → replayLast', () {
      expect(matcher.match('say  again'), isA<LocalCommandReplayLast>());
    });
  });

  group('LocalCommandMatcher — passthrough', () {
    // The originating production phrase that must NOT trigger replay.
    test(
        '"Powtórz, żeby coś przerwało." (origin [42]) → passthrough',
        () {
      expect(
        matcher.match('Powtórz, żeby coś przerwało.'),
        isA<LocalCommandPassthrough>(),
      );
    });

    test('"Powtórz ostatnią wygenerowaną wiadomość." → passthrough', () {
      expect(
        matcher.match('Powtórz ostatnią wygenerowaną wiadomość.'),
        isA<LocalCommandPassthrough>(),
      );
    });

    test('"powtórz, że X" → passthrough', () {
      expect(
        matcher.match('powtórz, że X'),
        isA<LocalCommandPassthrough>(),
      );
    });

    test('"Repeat please tell me more" → passthrough', () {
      expect(
        matcher.match('Repeat please tell me more'),
        isA<LocalCommandPassthrough>(),
      );
    });

    test('empty string → passthrough', () {
      expect(matcher.match(''), isA<LocalCommandPassthrough>());
    });

    test('whitespace-only "   " → passthrough', () {
      expect(matcher.match('   '), isA<LocalCommandPassthrough>());
    });

    test('pure punctuation "..." → passthrough', () {
      expect(matcher.match('...'), isA<LocalCommandPassthrough>());
    });

    test('substring inside larger sentence → passthrough', () {
      expect(
        matcher.match('Please repeat the answer'),
        isA<LocalCommandPassthrough>(),
      );
    });

    test('replayLast prefix with more words → passthrough', () {
      expect(
        matcher.match('powtórz to wszystko'),
        isA<LocalCommandPassthrough>(),
      );
    });
  });
}
