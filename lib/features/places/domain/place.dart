import 'dart:math' as math;

/// A place the owner named (personal-agent ADR-API-112). The phone makes the id,
/// so a repeated save changes nothing.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.radiusM,
    required this.tags,
    required this.storeTypes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Place.fromMap(Map<String, dynamic> map) => Place(
    id: map['id'] as String,
    name: map['name'] as String,
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
    accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
    radiusM: (map['radius_m'] as num).toInt(),
    tags: _strings(map['tags']),
    storeTypes: _strings(map['store_types']),
    createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
  );

  static List<String> _strings(Object? raw) =>
      (raw as List<dynamic>? ?? const []).cast<String>();

  /// The radius of a new place, the smallest Android's geofences are reliable at.
  static const defaultRadiusM = 150;

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int radiusM;
  final List<String> tags;
  final List<String> storeTypes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'radius_m': radiusM,
    'tags': tags,
    'store_types': storeTypes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Place copyWith({
    String? name,
    List<String>? tags,
    List<String>? storeTypes,
    DateTime? updatedAt,
  }) => Place(
    id: id,
    name: name ?? this.name,
    latitude: latitude,
    longitude: longitude,
    accuracyM: accuracyM,
    radiusM: radiusM,
    tags: tags ?? this.tags,
    storeTypes: storeTypes ?? this.storeTypes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Metres from this place's centre to the point (haversine, mean Earth
  /// radius); enough at the scale of a shop.
  double distanceTo(double latitude, double longitude) {
    const earthM = 6371000.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(latitude - this.latitude);
    final dLon = rad(longitude - this.longitude);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(this.latitude)) *
            math.cos(rad(latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * earthM * math.asin(math.sqrt(a));
  }

  /// The place [reading] stands in: of those whose radius holds it, the one
  /// with the nearest centre. Null when it stands in none.
  static Place? containing(Iterable<Place> places, PlaceReading reading) {
    Place? best;
    var bestM = double.infinity;
    for (final place in places) {
      final m = place.distanceTo(reading.latitude, reading.longitude);
      if (m <= place.radiusM && m < bestM) {
        best = place;
        bestM = m;
      }
    }
    return best;
  }

  /// Takes the whole position, so an old accuracy never outlives its reading.
  Place movedTo(PlaceReading reading) => Place(
    id: id,
    name: name,
    latitude: reading.latitude,
    longitude: reading.longitude,
    accuracyM: reading.accuracyM,
    radiusM: radiusM,
    tags: tags,
    storeTypes: storeTypes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// A type from the shopping catalogue, kept here so it can be chosen offline.
class PlaceStoreType {
  const PlaceStoreType({required this.id, required this.label});

  factory PlaceStoreType.fromMap(Map<String, dynamic> map) =>
      PlaceStoreType(id: map['id'] as String, label: map['label'] as String);

  final String id;
  final String label;

  Map<String, dynamic> toMap() => {'id': id, 'label': label};
}

/// Where the phone thinks it stands.
class PlaceReading {
  const PlaceReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.age,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;
  final Duration age;
}

enum PlaceReadingProblem {
  /// Location is refused; the system's settings can change that.
  permission,

  /// No position arrived, as with location off or no sky.
  noFix,

  /// This platform has no reading.
  unavailable,
}

/// A reading or why there is none: exactly one is set.
class PlaceReadingResult {
  const PlaceReadingResult.found(PlaceReading this.reading) : problem = null;
  const PlaceReadingResult.none(PlaceReadingProblem this.problem)
    : reading = null;

  final PlaceReading? reading;
  final PlaceReadingProblem? problem;
}
