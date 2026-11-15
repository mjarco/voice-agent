import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/theme/app_theme.dart';
import 'package:voice_agent/core/widgets/glass.dart';

Future<void> _pump(WidgetTester tester, Widget child, {ThemeMode mode = ThemeMode.light}) =>
    tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: Scaffold(body: Center(child: child)),
    ));

void main() {
  testWidgets('a card does not blur; a surface asked to blurs what is behind it', (tester) async {
    await _pump(tester, const Column(children: [
      GlassCard(key: Key('card'), child: Text('karta')),
      GlassSurface(key: Key('frosted'), blur: true, child: Text('pasek')),
    ]));
    expect(find.descendant(of: find.byKey(const Key('card')), matching: find.byType(BackdropFilter)), findsNothing);
    final filter = tester.widget<BackdropFilter>(
        find.descendant(of: find.byKey(const Key('frosted')), matching: find.byType(BackdropFilter)));
    expect(filter.filter, ImageFilter.blur(sigmaX: GlassSurface.sigma, sigmaY: GlassSurface.sigma));
  });

  testWidgets('a glass list splits its rows with hairlines in the glass line', (tester) async {
    await _pump(tester, const GlassList(children: [
      GlassRow(title: 'Telefon do mamy', leading: GlassPill('13:30')),
      GlassRow(title: 'Trening', trailing: Text('45 min')),
      GlassRow(title: 'Spacer', done: true),
    ]));
    final lines = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(lines, hasLength(2));
    expect(lines.first.color, AppColors.light.glassLine);
    final done = tester.widget<Text>(find.text('Spacer'));
    expect(done.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('an overdue pill takes the warning, in either mode', (tester) async {
    for (final (mode, colors) in [(ThemeMode.light, AppColors.light), (ThemeMode.dark, AppColors.dark)]) {
      await _pump(tester, const GlassPill('zaległe', warning: true), mode: mode);
      await tester.pumpAndSettle();
      final box = tester.widget<Container>(
          find.ancestor(of: find.text('zaległe'), matching: find.byType(Container)).first);
      expect((box.decoration as BoxDecoration).color, colors.warning);
    }
  });

  testWidgets('the tab bar floats as frosted glass, icons only, the current tab in ink', (tester) async {
    var picked = -1;
    await _pump(
      tester,
      GlassTabBar(
        bar: NavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (i) => picked = i,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Dziś'),
            NavigationDestination(icon: Icon(Icons.event_outlined), label: 'Agenda'),
          ],
        ),
      ),
    );
    expect(
      find.descendant(of: find.byKey(const Key('glass-tab-bar')), matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
    expect(theme.indicatorColor, AppTheme.lightScheme.onSurface);
    await tester.tap(find.byIcon(Icons.wb_sunny_outlined));
    expect(picked, 0);
  });

  testWidgets('a round glass button keeps its key and its tooltip', (tester) async {
    var tapped = false;
    await _pump(tester, GlassIconButton(key: const Key('b'), icon: Icons.tune, tooltip: 'Ustawienia', onPressed: () => tapped = true));
    expect(tester.getSize(find.byKey(const Key('b'))), const Size(42, 42));
    await tester.tap(find.byKey(const Key('b')));
    expect(tapped, isTrue);
    expect(find.byTooltip('Ustawienia'), findsOneWidget);
  });

  testWidgets('a number counts to its new value and ends there', (tester) async {
    Widget at(int v) => MaterialApp(home: Scaffold(body: CountingNumber(v, textKey: const Key('n'))));
    String shown() => tester.widget<Text>(find.byKey(const Key('n'))).data!;
    await tester.pumpWidget(at(2200));
    expect(shown(), '2200', reason: 'the first value shows as it is');
    await tester.pumpWidget(at(1780));
    await tester.pump(const Duration(milliseconds: 150));
    final mid = int.parse(shown());
    expect(mid, inExclusiveRange(1780, 2200));
    await tester.pumpAndSettle();
    expect(shown(), '1780');
  });

  testWidgets('with "Remove animations" a number changes at once', (tester) async {
    Widget at(int v) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: CountingNumber(v, textKey: const Key('n'))),
          ),
        );
    await tester.pumpWidget(at(2200));
    await tester.pumpWidget(at(1780));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('n'))).data, '1780');
  });
}
