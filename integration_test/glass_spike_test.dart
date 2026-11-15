// The blur spike of off-roadmap S2 (2026-11-15-va-graphite-glass): Dziś-like
// glass over the drifting sky, scrolled on the phone in a profile build, with
// live blur on every card and without it. Frame times, not looks, decide.
//
//   flutter drive --profile --flavor dev -d <serial> \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/glass_spike_test.dart
//
// The summaries land in build/glass_spike_<variant>.timeline_summary.json.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_agent/core/theme/app_theme.dart';
import 'package:voice_agent/core/widgets/aurora_background.dart';
import 'package:voice_agent/core/widgets/glass.dart';

class _SpikePage extends StatelessWidget {
  const _SpikePage({required this.cardsBlur});

  final bool cardsBlur;

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: ListView(
          key: const Key('spike-list'),
          padding: const EdgeInsets.only(top: 48, bottom: 180),
          children: [
            for (var i = 0; i < 14; i++) ...[
              const SectionLabel('Agenda'),
              if (i.isEven)
                GlassSurface(
                  radius: 28,
                  blur: cardsBlur,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  child: Text('${1240 - i * 10}', style: Theme.of(context).textTheme.displayMedium),
                )
              else
                GlassSurface(
                  blur: cardsBlur,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    for (var j = 0; j < 4; j++)
                      GlassRow(leading: const GlassPill('13:30'), title: 'Telefon do mamy $i.$j', trailing: const Text('45 min')),
                  ]),
                ),
            ],
          ],
        ),
        bottomNavigationBar: GlassTabBar(
          bar: NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Dziś'),
              NavigationDestination(icon: Icon(Icons.event_outlined), label: 'Agenda'),
              NavigationDestination(icon: Icon(Icons.folder_open_outlined), label: 'Sprawy'),
              NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'Zakupy'),
              NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Rozmowy'),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final (variant, cardsBlur) in [('blur', true), ('translucent', false)]) {
    testWidgets('scroll Dziś-like glass, cards $variant', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AuroraDrift(enabled: true, child: _SpikePage(cardsBlur: cardsBlur)),
      ));
      await tester.pump(const Duration(seconds: 1));
      final list = find.byKey(const Key('spike-list'));
      await binding.traceAction(() async {
        for (var k = 0; k < 6; k++) {
          await tester.fling(list, const Offset(0, -900), 2500);
          await tester.pump(const Duration(milliseconds: 900));
          await tester.fling(list, const Offset(0, 900), 2500);
          await tester.pump(const Duration(milliseconds: 900));
        }
      }, reportKey: 'glass_spike_$variant');
    });
  }
}
