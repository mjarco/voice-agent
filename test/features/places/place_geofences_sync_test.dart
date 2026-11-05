import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';
import 'package:voice_agent/features/places/presentation/place_geofences_sync.dart';
import 'package:voice_agent/features/places/presentation/places_providers.dart';

import 'fakes.dart';

class _FakeGeofencesPort implements PlaceGeofencesPort {
  final sent = <List<String>>[];
  final names = <Map<String, String>>[];
  Object? failure;

  @override
  Future<void> setPlaces(List<Place> places) async {
    sent.add([for (final p in places) p.id]);
    names.add({for (final p in places) p.id: p.name});
    if (failure != null) throw failure!;
  }
}

void main() {
  late FakePlacesRepository repository;
  late FakePlacesStore store;
  late _FakeGeofencesPort port;

  ProviderContainer container({bool available = true}) {
    final c = ProviderContainer(
      overrides: [
        placesRepositoryProvider.overrideWithValue(repository),
        placesLocalStoreProvider.overrideWithValue(store),
        placeGeofencesPortProvider.overrideWithValue(port),
        placeGeofencesAvailableProvider.overrideWithValue(available),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    repository = FakePlacesRepository();
    store = FakePlacesStore(
      PlacesSnapshot(
        places: [
          place('a', at: DateTime.utc(2026, 11, 2)),
          place('b', at: DateTime.utc(2026, 11, 1)),
        ],
      ),
    );
    port = _FakeGeofencesPort();
  });

  test('sends once the copy is loaded, not before', () async {
    final c = container();
    c.read(placeGeofencesSyncProvider);
    expect(port.sent, isEmpty);
    await pumpEventQueue();
    expect(port.sent, [
      ['a', 'b'],
    ]);
  });

  test(
    'sends after a change, and nothing while the copy is unchanged',
    () async {
      final c = container();
      c.read(placeGeofencesSyncProvider);
      await pumpEventQueue();
      final notifier = c.read(placesNotifierProvider.notifier);

      // A sync that brings back the same places changes nothing here.
      repository.server.addAll({
        'a': place('a', at: DateTime.utc(2026, 11, 2)),
        'b': place('b', at: DateTime.utc(2026, 11, 1)),
      });
      await notifier.sync();
      await pumpEventQueue();
      expect(port.sent, hasLength(1));

      await notifier.save(place('c', at: DateTime.utc(2026, 11, 3)));
      await pumpEventQueue();
      expect(port.sent.last, ['c', 'a', 'b']);

      // A rename is sent: the rows carry the place's name.
      final beforeRename = port.sent.length;
      await notifier.save(place('a', name: 'Castorama'));
      await pumpEventQueue();
      expect(port.sent, hasLength(beforeRename + 1));
      expect(port.sent.last, containsAll(['a', 'b', 'c']));
      expect(port.names.last['a'], 'Castorama');
      final count = port.sent.length;

      await notifier.sync();
      await pumpEventQueue();
      expect(port.sent, hasLength(count));
    },
  );

  test('a change of tags alone sends nothing', () async {
    final c = container();
    c.read(placeGeofencesSyncProvider);
    await pumpEventQueue();
    final notifier = c.read(placesNotifierProvider.notifier);
    final a = place('a', at: DateTime.utc(2026, 11, 2));
    repository.server.addAll({'a': a, 'b': place('b', at: DateTime.utc(2026, 11, 1))});
    await notifier.sync();
    await pumpEventQueue();
    expect(port.sent, hasLength(1));

    await notifier.save(
          Place(
            id: a.id,
            name: a.name,
            latitude: a.latitude,
            longitude: a.longitude,
            accuracyM: a.accuracyM,
            radiusM: a.radiusM,
            tags: const ['dom'],
            storeTypes: a.storeTypes,
            createdAt: a.createdAt,
            updatedAt: DateTime.utc(2026, 11, 3),
          ),
        );
    await pumpEventQueue();
    expect(port.sent, hasLength(1));
  });

  test('leaves out places waiting to be deleted', () async {
    store = FakePlacesStore(
      PlacesSnapshot(
        places: [place('a'), place('b')],
        pendingDeletes: const {'b'},
      ),
    );
    repository.failure = const PlacesException('offline', temporary: true);
    final c = container();
    c.read(placeGeofencesSyncProvider);
    await pumpEventQueue();
    expect(port.sent.single, ['a']);

    await c.read(placesNotifierProvider.notifier).remove('a');
    await pumpEventQueue();
    expect(port.sent.last, isEmpty);
  });

  test('a failed hand-over is tried again at the next change', () async {
    port.failure = Exception('no engine');
    final c = container();
    c.read(placeGeofencesSyncProvider);
    await pumpEventQueue();
    expect(port.sent, hasLength(1));

    port.failure = null;
    repository.failure = const PlacesException('offline', temporary: true);
    await c.read(placesNotifierProvider.notifier).sync();
    await pumpEventQueue();
    expect(port.sent, hasLength(2));
  });

  test('does nothing off Android', () async {
    final c = container(available: false);
    c.read(placeGeofencesSyncProvider);
    await pumpEventQueue();
    expect(port.sent, isEmpty);
  });
}
