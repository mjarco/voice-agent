import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/recording/presentation/mic_activity.dart';
import 'package:voice_agent/features/recording/presentation/mic_orb.dart';

/// Pumps an orb in [activity] and returns whether it asks for frames.
Future<void> _pumpOrb(
  WidgetTester tester,
  MicActivity activity, {
  bool disableAnimations = false,
}) =>
    tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Center(
          child: MicOrb(
            activity: activity,
            color: Colors.teal,
            child: const SizedBox(width: 46, height: 46),
          ),
        ),
      ),
    ));

void main() {
  setUp(() => MicOrb.debugAnimate = true);
  tearDown(() => MicOrb.debugAnimate = false);

  for (final a in MicActivity.values) {
    testWidgets('the orb in ${a.name} ${a == MicActivity.standby ? 'stands still' : 'moves'}',
        (tester) async {
      await _pumpOrb(tester, a);
      expect(find.byKey(Key('mic-orb-${a.name}')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.binding.hasScheduledFrame || a == MicActivity.idle,
        a != MicActivity.standby,
        reason: 'every state but standby loops (idle on its own timer)',
      );
      // Unmounting stops the loop and the idle timer.
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('idle breathes on a timer, not on every frame', (tester) async {
    await _pumpOrb(tester, MicActivity.idle);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'no ticker: the next frame waits for the timer');
    double scale() => tester
        .widget<Transform>(find.descendant(
            of: find.byKey(const Key('mic-orb-idle')), matching: find.byType(Transform)))
        .transform
        .getMaxScaleOnAxis();
    final before = scale();
    await tester.pump(const Duration(milliseconds: 900));
    expect(scale(), isNot(before), reason: 'the timer moved the breath');
    await tester.pumpWidget(const SizedBox());
  });

  for (final a in [MicActivity.idle, MicActivity.listening, MicActivity.recording, MicActivity.processing]) {
    testWidgets('Android\'s "Remove animations" stills the orb in ${a.name}', (tester) async {
      await _pumpOrb(tester, a, disableAnimations: true);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('a new state takes the new motion', (tester) async {
    await _pumpOrb(tester, MicActivity.listening);
    await tester.pump(const Duration(milliseconds: 100));
    await _pumpOrb(tester, MicActivity.processing);
    expect(find.byKey(const Key('mic-orb-processing')), findsOneWidget);
    expect(find.byKey(const Key('mic-orb-listening')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
