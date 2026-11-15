import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/theme/app_theme.dart';
import 'package:voice_agent/core/widgets/aurora_background.dart';

/// Pumps a sky under [AuroraDrift] and returns a reader of its phase.
Future<double Function()> _pumpSky(
  WidgetTester tester, {
  required bool enabled,
  bool disableAnimations = false,
}) async {
  late BuildContext skyContext;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: AuroraDrift(
        enabled: enabled,
        child: AuroraBackground(
          child: Builder(builder: (context) {
            skyContext = context;
            return const SizedBox.expand();
          }),
        ),
      ),
    ),
  ));
  return () => AuroraDrift.of(skyContext).value;
}

void main() {
  setUp(() => AuroraDrift.debugEnabled = true);
  tearDown(() => AuroraDrift.debugEnabled = false);

  testWidgets('the sky drifts while "Tło w ruchu" is on', (tester) async {
    final phase = await _pumpSky(tester, enabled: true);
    await tester.pump(const Duration(seconds: 1));
    final first = phase();
    await tester.pump(const Duration(seconds: 3));
    expect(phase(), greaterThan(first));
    expect(find.byKey(const Key('aurora-background')), findsWidgets);
  });

  testWidgets('"Tło w ruchu" off: the sky stands still and no frame is asked for', (tester) async {
    final phase = await _pumpSky(tester, enabled: false);
    await tester.pump(const Duration(seconds: 3));
    expect(phase(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Android\'s "Remove animations" stops the drift too', (tester) async {
    final phase = await _pumpSky(tester, enabled: true, disableAnimations: true);
    await tester.pump(const Duration(seconds: 3));
    expect(phase(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the app in the background stops the drift, the return resumes it', (tester) async {
    final phase = await _pumpSky(tester, enabled: true);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final stopped = phase();
    await tester.pump(const Duration(seconds: 5));
    expect(phase(), stopped);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), greaterThan(stopped), reason: 'it goes on from where it stood');
  });

  testWidgets('every page route draws the sky behind its page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: Text('home')),
    ));
    expect(find.byKey(const Key('aurora-background')), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
          Theme.of(tester.element(find.text('home'))).scaffoldBackgroundColor,
      Colors.transparent,
    );
  });
}
