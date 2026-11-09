import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_screen.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';
import 'package:voice_agent/features/pins/presentation/pins_screen.dart';

class _StubRepository implements PinsRepository {
  List<PinSummary> pins;
  Exception? fetchError;
  Exception? unpinError;
  String? lastUnpinId;

  _StubRepository({this.pins = const []});

  @override
  Future<List<PinSummary>> fetchPins() async {
    if (fetchError != null) throw fetchError!;
    return pins;
  }

  @override
  Future<PinDetail> fetchPin(String recordId) async => PinDetail(
        recordId: recordId,
        pinName: 'pin $recordId',
        text: '# Detail $recordId',
        createdAt: DateTime.utc(2026, 6, 15),
      );

  @override
  Future<void> unpin(String recordId) async {
    lastUnpinId = recordId;
    if (unpinError != null) throw unpinError!;
    // Reflect the backend soft-delete so a subsequent re-fetch omits the row.
    pins = pins.where((p) => p.recordId != recordId).toList();
  }
}

PinSummary _pin(String id) => PinSummary(
      recordId: id,
      pinName: 'Pin $id',
      createdAt: DateTime.utc(2026, 6, 15),
    );

Future<void> _pump(WidgetTester tester, PinsRepository repo) async {
  final router = GoRouter(
    initialLocation: '/pins',
    routes: [
      GoRoute(
        path: '/pins',
        builder: (context, state) => const PinsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Close form'),
              ),
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => Scaffold(
              body: Text('Detail ${state.pathParameters['id']}'),
            ),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [pinsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PinsScreen', () {
    testWidgets('renders the Pins app bar title', (tester) async {
      await _pump(tester, _StubRepository(pins: [_pin('a')]));

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Pins')),
        findsOneWidget,
      );
    });

    testWidgets('renders a tile per pin', (tester) async {
      await _pump(
        tester,
        _StubRepository(pins: [_pin('a'), _pin('b')]),
      );

      expect(find.byKey(const Key('pin-tile-a')), findsOneWidget);
      expect(find.byKey(const Key('pin-tile-b')), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no pins',
        (tester) async {
      await _pump(tester, _StubRepository(pins: const []));

      expect(find.textContaining('No pins yet'), findsOneWidget);
    });

    testWidgets('shows the error state with retry on fetch failure',
        (tester) async {
      await _pump(
        tester,
        _StubRepository()..fetchError = Exception('network'),
      );

      expect(find.byKey(const Key('pins-retry-button')), findsOneWidget);
    });

    for (final (name, repo) in [
      ('the empty state', _StubRepository()),
      ('the error state', _StubRepository()..fetchError = Exception('network')),
    ]) {
      testWidgets('"+" is on $name', (tester) async {
        await _pump(tester, repo);

        expect(find.byKey(const Key('pins-add')), findsOneWidget);
      });
    }

    testWidgets('"+" leaves the last row\'s menu reachable', (tester) async {
      final repo = _StubRepository(
        pins: [for (var i = 0; i < 30; i++) _pin('p$i')],
      );
      await _pump(tester, repo);

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byKey(const Key('pin-menu-p29')));
      final add = tester.getRect(find.byKey(const Key('pins-add')));

      expect(menu.overlaps(add), isFalse);
    });

    testWidgets('"+" opens the form and the list reloads on return',
        (tester) async {
      final repo = _StubRepository(pins: [_pin('a')]);
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pins-add')));
      await tester.pumpAndSettle();
      repo.pins = [_pin('b'), _pin('a')];
      await tester.tap(find.text('Close form'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pin-tile-b')), findsOneWidget);
    });

    // personal-agent R2 (ADR-CORE-117): a pin has no topic, so the list is
    // one list, newest first, each row dated.
    testWidgets('lists pins without a view toggle or topic headers',
        (tester) async {
      await _pump(tester, _StubRepository(pins: [_pin('a'), _pin('b')]));

      expect(find.byKey(const Key('pin-tile-a')), findsOneWidget);
      expect(find.byKey(const Key('pin-tile-b')), findsOneWidget);
      expect(find.text('By topic'), findsNothing);
      expect(find.text('Recent'), findsNothing);
      expect(find.text('No topic'), findsNothing);
      expect(find.byType(SegmentedButton<Object>), findsNothing);
      expect(find.text('2026-06-15'), findsNWidgets(2));
    });

    testWidgets('tapping a pin navigates to its detail route', (tester) async {
      await _pump(tester, _StubRepository(pins: [_pin('a')]));

      await tester.tap(find.byKey(const Key('pin-tile-a')));
      await tester.pumpAndSettle();

      expect(find.text('Detail a'), findsOneWidget);
    });

    testWidgets('unpin via the tile menu calls the repository',
        (tester) async {
      final repo = _StubRepository(pins: [_pin('a')]);
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pin-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-unpin-confirm')));
      await tester.pumpAndSettle();

      expect(repo.lastUnpinId, 'a');
      expect(find.byKey(const Key('pin-tile-a')), findsNothing);
    });

    // ADR-ARCH-011 seam: unpinning from the detail screen must drop the row
    // from the list on return (via the tile's awaited-push + refresh()).
    testWidgets('unpinning from the detail screen removes the row on return',
        (tester) async {
      final repo = _StubRepository(pins: [_pin('a'), _pin('b')]);
      final router = GoRouter(
        initialLocation: '/pins',
        routes: [
          GoRoute(
            path: '/pins',
            builder: (context, state) => const PinsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    PinDetailScreen(recordId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [pinsRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Open detail for pin a.
      await tester.tap(find.byKey(const Key('pin-tile-a')));
      await tester.pumpAndSettle();

      // Unpin from the detail screen and confirm.
      await tester.tap(find.byKey(const Key('pin-detail-unpin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-detail-unpin-confirm')));
      await tester.pumpAndSettle();

      // Back on the list, the row is gone (refresh re-fetched the reduced set).
      expect(repo.lastUnpinId, 'a');
      expect(find.byKey(const Key('pin-tile-a')), findsNothing);
      expect(find.byKey(const Key('pin-tile-b')), findsOneWidget);
    });
  });
}
