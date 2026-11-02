import 'dart:async';

import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';

Place place(String id, {String name = 'Leroy', DateTime? at}) {
  final time = at ?? DateTime.utc(2026, 11, 2, 10);
  return Place(
    id: id,
    name: name,
    latitude: 52.25,
    longitude: 21.01,
    accuracyM: 12,
    radiusM: 150,
    tags: const ['sklep'],
    storeTypes: const ['diy'],
    createdAt: time,
    updatedAt: time,
  );
}

class FakePlacesRepository implements PlacesRepository {
  final server = <String, Place>{};
  final puts = <String>[];
  final deletes = <String>[];
  PlacesException? failure;
  PlacesException? failPutOf;
  String? failPutId;
  void Function()? onPut;

  @override
  Future<List<Place>> fetchPlaces() async {
    if (failure != null) throw failure!;
    return server.values.toList();
  }

  @override
  Future<List<PlaceStoreType>> fetchStoreTypes() async => const [
    PlaceStoreType(id: 'diy', label: 'Budowlany'),
  ];

  @override
  Future<Place> put(Place place) async {
    if (failure != null) throw failure!;
    if (place.id == failPutId) throw failPutOf!;
    puts.add(place.id);
    onPut?.call();
    return server[place.id] = place;
  }

  @override
  Future<void> delete(String id) async {
    if (failure != null) throw failure!;
    deletes.add(id);
    server.remove(id);
  }
}

class FakePlacesStore implements PlacesLocalStore {
  FakePlacesStore([this.snapshot = const PlacesSnapshot()]);

  PlacesSnapshot snapshot;

  /// When set, a save waits for it, as a slow disk would.
  Completer<void>? gate;

  @override
  Future<PlacesSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlacesSnapshot snapshot) async {
    await gate?.future;
    this.snapshot = snapshot;
  }
}

class FakeReadingPort implements PlaceReadingPort {
  FakeReadingPort(this.result);

  PlaceReadingResult result;
  int settings = 0;
  int reads = 0;

  /// When set, a reading waits for it, as a fix does.
  Completer<void>? gate;

  @override
  Future<PlaceReadingResult> read() async {
    reads++;
    await gate?.future;
    return result;
  }

  @override
  Future<void> openSettings() async => settings++;
}
