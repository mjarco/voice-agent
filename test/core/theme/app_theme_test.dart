import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/theme/app_theme.dart';

double _luminance(Color c) => c.computeLuminance();

/// WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, theme, colors) in [
    ('light', AppTheme.light(), AppColors.light),
    ('dark', AppTheme.dark(), AppColors.dark),
  ]) {
    group('Graphite $name', () {
      test('carries AppColors, Sora and its brightness', () {
        expect(theme.extension<AppColors>(), same(colors));
        expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
        expect(theme.colorScheme.brightness, name == 'light' ? Brightness.light : Brightness.dark);
      });

      test('text reads on its surfaces (WCAG AA 4.5:1)', () {
        final s = theme.colorScheme;
        expect(_contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(s.onSurfaceVariant, s.surfaceContainerHigh), greaterThanOrEqualTo(4.5));
        expect(_contrast(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(4.5));
        expect(_contrast(s.onErrorContainer, s.errorContainer), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.onWarningContainer, colors.warningContainer), greaterThanOrEqualTo(4.5));
      });

      test('filled accents and the mic carry their icon (3:1, non-text)', () {
        final s = theme.colorScheme;
        expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(3));
        expect(_contrast(s.onError, s.error), greaterThanOrEqualTo(3));
        expect(_contrast(colors.onSuccess, colors.success), greaterThanOrEqualTo(3));
        expect(_contrast(colors.onWarning, colors.warning), greaterThanOrEqualTo(3));
        for (final mic in [colors.micRecording, colors.micIdle, colors.micStandby]) {
          expect(_contrast(colors.onMic, mic), greaterThanOrEqualTo(3), reason: '$mic');
        }
      });

      test('the mic states stay four distinct colours', () {
        final states = {colors.micRecording, colors.micListening, colors.micProcessing, colors.micIdle, colors.micStandby};
        expect(states, hasLength(5));
      });
    });
  }

  testWidgets('AppColors.of falls back to the palette of the brightness', (tester) async {
    late AppColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(builder: (context) {
        seen = AppColors.of(context);
        return const SizedBox();
      }),
    ));
    expect(seen, same(AppColors.dark));
  });
}
