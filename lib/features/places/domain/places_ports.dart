import 'package:voice_agent/features/places/domain/place.dart';

/// A failed call. [temporary] means the next try may work: no link, PA down.
class PlacesException implements Exception {
  const PlacesException(this.message, {required this.temporary});

  final String message;
  final bool temporary;

  @override
  String toString() => message;
}

/// Places in personal-agent.
abstract class PlacesRepository {
  Future<List<Place>> fetchPlaces();
  Future<List<PlaceStoreType>> fetchStoreTypes();

  /// Saves and returns what is stored, the newer place when this one came late.
  Future<Place> put(Place place);
  Future<void> delete(String id);
}

/// What the phone keeps, so the list and a save work with no link.
class PlacesSnapshot {
  const PlacesSnapshot({
    this.places = const [],
    this.pendingPuts = const {},
    this.pendingDeletes = const {},
    this.storeTypes = const [],
  });

  final List<Place> places;
  final Set<String> pendingPuts;
  final Set<String> pendingDeletes;
  final List<PlaceStoreType> storeTypes;
}

abstract class PlacesLocalStore {
  Future<PlacesSnapshot> load();
  Future<void> save(PlacesSnapshot snapshot);
}

/// One fresh position.
abstract class PlaceReadingPort {
  Future<PlaceReadingResult> read();
  Future<void> openSettings();
}
