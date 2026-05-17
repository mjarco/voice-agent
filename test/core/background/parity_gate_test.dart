// Parity-gate test per ADR-PLATFORM-007.
//
// Foreground init (`app_main.dart`) and the workmanager isolate entrypoint
// (`app/background/agenda_refresh_entrypoint.dart`) must both construct
// dependencies via the two shared helpers (`coreBoot` + `wireAgendaForBackground`)
// and nothing else. If a future refactor adds a step outside these helpers,
// this test fails — drift is caught at CI, not on a device after iOS BGTask
// flakiness obscures it.
//
// The test asserts via static source inspection: each entry-point file is
// expected to import both helpers and call both function names exactly once.
// It does NOT execute the helpers themselves (those require SharedPreferences,
// SQLite, and platform plugins that aren't available in the test harness).
//
// What this test catches:
// - A future foreground refactor that open-codes SQLite init (skipping coreBoot).
// - A future foreground refactor that constructs ApiAgendaRepository directly
//   (skipping wireAgendaForBackground).
// - A new background entrypoint that forgets either helper.
//
// What this test does NOT catch:
// - Runtime divergence between core boot in the two contexts (manual
//   verification on a real device covers that).
// - Mismatches in the override list shape (a separate compile-time check).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Foreground init (app_main.dart) parity', () {
    final source = File('lib/app_main.dart').readAsStringSync();

    test('imports coreBoot', () {
      expect(
        source.contains(
          'package:voice_agent/core/background/workmanager_core_boot.dart',
        ),
        isTrue,
        reason: 'app_main.dart must import coreBoot helper',
      );
    });

    test('imports wireAgendaForBackground', () {
      expect(
        source.contains(
          'package:voice_agent/app/background/wire_agenda_for_background.dart',
        ),
        isTrue,
        reason: 'app_main.dart must import wireAgendaForBackground helper',
      );
    });

    test('calls coreBoot() exactly once (in code, not in comments)', () {
      final stripped = _stripComments(source);
      final count = 'coreBoot()'.allMatches(stripped).length;
      expect(count, 1,
          reason:
              'foreground must call coreBoot exactly once; found $count calls');
    });

    test('calls wireAgendaForBackground() exactly once', () {
      final stripped = _stripComments(source);
      final count = 'wireAgendaForBackground('.allMatches(stripped).length;
      expect(count, 1,
          reason: 'foreground must call wireAgendaForBackground exactly '
              'once; found $count calls');
    });
  });

  group('Background entrypoint parity', () {
    final source = File('lib/app/background/agenda_refresh_entrypoint.dart')
        .readAsStringSync();

    test('imports coreBoot', () {
      expect(
        source.contains(
          'package:voice_agent/core/background/workmanager_core_boot.dart',
        ),
        isTrue,
      );
    });

    test('imports wireAgendaForBackground', () {
      expect(
        source.contains(
          'package:voice_agent/app/background/wire_agenda_for_background.dart',
        ),
        isTrue,
      );
    });

    test('calls coreBoot() exactly once (in code, not in comments)', () {
      final stripped = _stripComments(source);
      final count = 'coreBoot()'.allMatches(stripped).length;
      expect(count, 1,
          reason: 'bg entrypoint must call coreBoot exactly once; found $count');
    });

    test('calls wireAgendaForBackground() exactly once', () {
      final stripped = _stripComments(source);
      final count = 'wireAgendaForBackground('.allMatches(stripped).length;
      expect(count, 1,
          reason: 'bg entrypoint must call wireAgendaForBackground exactly '
              'once; found $count calls');
    });

    test('is annotated @pragma vm:entry-point', () {
      expect(source.contains("@pragma('vm:entry-point')"), isTrue,
          reason: 'workmanager isolate entry function must survive '
              'tree-shaking');
    });
  });

  group('Layer separation', () {
    test('core/background/workmanager_core_boot.dart does not import features/',
        () {
      final source = File('lib/core/background/workmanager_core_boot.dart')
          .readAsStringSync();
      final hasFeatureImport =
          source.contains('package:voice_agent/features/');
      expect(hasFeatureImport, isFalse,
          reason: 'ADR-ARCH-003: core/ must not import features/');
    });
  });
}

/// Removes `//` line comments and `///` doc comments. Naive — does not
/// handle string literals containing `//`. Good enough for our source files.
String _stripComments(String source) {
  return source
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');
}
