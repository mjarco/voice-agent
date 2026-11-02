import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/presentation/places_providers.dart';
import 'package:voice_agent/features/places/presentation/places_screen.dart';

import 'fakes.dart';

const _reading = PlaceReading(
  latitude: 52.25,
  longitude: 21.01,
  accuracyM: 14,
  age: Duration.zero,
);

void main() {
  late FakePlacesRepository repository;
  late FakeReadingPort port;
  late FakePlacesStore store;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          placesRepositoryProvider.overrideWithValue(repository),
          placesLocalStoreProvider.overrideWithValue(store),
          placeReadingPortProvider.overrideWithValue(port),
        ],
        child: const MaterialApp(home: PlacesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    repository = FakePlacesRepository();
    store = FakePlacesStore();
    port = FakeReadingPort(const PlaceReadingResult.found(_reading));
  });

  testWidgets('shows the reading and saves in two taps with a name', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('±14 m'), findsOneWidget);

    final save = find.byKey(const Key('places-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('places-name')), ' Leroy ');
    await tester.pump();
    await tester.tap(find.text('sklep'));
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final saved = repository.server.values.single;
    expect(saved.name, 'Leroy');
    expect(saved.tags, ['sklep']);
    expect(saved.radiusM, Place.defaultRadiusM);
    expect(saved.accuracyM, 14);
    expect(find.text('Leroy'), findsOneWidget);
    expect(find.text('Czeka na wysłanie: 1'), findsNothing);
  });

  testWidgets('with no reading it says why and offers the settings', (
    tester,
  ) async {
    port.result = const PlaceReadingResult.none(PlaceReadingProblem.permission);
    await pump(tester);
    expect(find.text('Brak zgody na lokalizację'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('places-name')), 'Dom');
    await tester.pump();
    final save = find.byKey(const Key('places-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.text('Otwórz ustawienia'));
    expect(port.settings, 1);
  });

  testWidgets('a place can be renamed, moved and deleted', (tester) async {
    repository.server['p1'] = place('p1');
    await pump(tester);

    await tester.tap(find.text('Leroy'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('places-edit-name')),
      'Leroy 2',
    );
    port.result = const PlaceReadingResult.found(
      PlaceReading(
        latitude: 50,
        longitude: 20,
        accuracyM: 5,
        age: Duration.zero,
      ),
    );
    await tester.tap(find.byKey(const Key('places-move-here')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('places-edit-save')));
    await tester.pumpAndSettle();
    expect(repository.server['p1']!.name, 'Leroy 2');
    expect(repository.server['p1']!.latitude, 50);

    await tester.tap(find.text('Leroy 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('places-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('places-delete-confirm')));
    await tester.pumpAndSettle();
    expect(repository.server, isEmpty);
    expect(find.text('Leroy 2'), findsNothing);
  });
  void comeBack(WidgetTester tester) {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('coming back to the app does not save where you were', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('places-name')), 'Obi');
    await tester.pump();

    port.gate = Completer<void>();
    port.result = const PlaceReadingResult.found(
      PlaceReading(
        latitude: 50,
        longitude: 20,
        accuracyM: 9,
        age: Duration.zero,
      ),
    );
    comeBack(tester);
    await tester.pump();

    final save = find.byKey(const Key('places-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    port.gate!.complete();
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.server.values.single.latitude, 50);
  });

  testWidgets('a permission dialog does not start a second reading', (
    tester,
  ) async {
    port.gate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          placesRepositoryProvider.overrideWithValue(repository),
          placesLocalStoreProvider.overrideWithValue(store),
          placeReadingPortProvider.overrideWithValue(port),
        ],
        child: const MaterialApp(home: PlacesScreen()),
      ),
    );
    await tester.pump();
    comeBack(tester);
    await tester.pump();
    expect(port.reads, 1);
    port.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a double tap makes one place', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('places-name')), 'Obi');
    await tester.pump();
    store.gate = Completer<void>();
    final save = find.byKey(const Key('places-save'));
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(repository.server, hasLength(1));
  });

  testWidgets('moving to a reading with no accuracy drops the old accuracy', (
    tester,
  ) async {
    repository.server['p1'] = place('p1');
    await pump(tester);
    await tester.tap(find.text('Leroy'));
    await tester.pumpAndSettle();
    port.result = const PlaceReadingResult.found(
      PlaceReading(
        latitude: 50,
        longitude: 20,
        accuracyM: null,
        age: Duration.zero,
      ),
    );
    await tester.tap(find.byKey(const Key('places-move-here')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('places-edit-save')));
    await tester.pumpAndSettle();
    expect(repository.server['p1']!.latitude, 50);
    expect(repository.server['p1']!.accuracyM, isNull);
  });
}
