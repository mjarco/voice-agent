/// A place the owner named (personal-agent ADR-API-111). The phone makes the id,
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
    double? latitude,
    double? longitude,
    double? accuracyM,
    List<String>? tags,
    List<String>? storeTypes,
    DateTime? updatedAt,
  }) => Place(
    id: id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    accuracyM: accuracyM ?? this.accuracyM,
    radiusM: radiusM,
    tags: tags ?? this.tags,
    storeTypes: storeTypes ?? this.storeTypes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
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
