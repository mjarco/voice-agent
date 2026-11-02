import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';

/// Keeps the snapshot as one JSON value: places are few, and they stand apart
/// from the transcript database and its migrations (ADR-NET-006).
class PrefsPlacesStore implements PlacesLocalStore {
  static const _key = 'places_snapshot_v1';

  @override
  Future<PlacesSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const PlacesSnapshot();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return PlacesSnapshot(
      places: (map['places'] as List<dynamic>)
          .map((e) => Place.fromMap(e as Map<String, dynamic>))
          .toList(),
      pendingPuts: (map['pending_puts'] as List<dynamic>)
          .cast<String>()
          .toSet(),
      pendingDeletes: (map['pending_deletes'] as List<dynamic>)
          .cast<String>()
          .toSet(),
      storeTypes: (map['store_types'] as List<dynamic>)
          .map((e) => PlaceStoreType.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> save(PlacesSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'places': snapshot.places.map((p) => p.toMap()).toList(),
        'pending_puts': snapshot.pendingPuts.toList(),
        'pending_deletes': snapshot.pendingDeletes.toList(),
        'store_types': snapshot.storeTypes.map((t) => t.toMap()).toList(),
      }),
    );
  }
}
