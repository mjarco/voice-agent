import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/presentation/places_notifier.dart';
import 'package:voice_agent/features/places/presentation/places_providers.dart';

/// Hands the places to the phone's geofences (ADR-PLATFORM-010) once the local
/// copy is loaded and after each change, leaving out places waiting to be
/// deleted. An unchanged copy sends nothing. It serves until task 4, which
/// takes the geofences from the triggers. A failure here must never reach the
/// rest of the app.
final placeGeofencesSyncProvider = Provider<void>((ref) {
  if (!ref.watch(placeGeofencesAvailableProvider)) return;
  final port = ref.watch(placeGeofencesPortProvider);
  List<String>? sent;

  Future<void> send(PlacesState state) async {
    if (!state.loaded) return;
    final places = [
      for (final p in state.places)
        if (!state.pendingDeletes.contains(p.id)) p,
    ];
    final key = places.map(_keyOf).toList();
    if (listEquals(sent, key)) return;
    sent = key;
    try {
      await port.setPlaces(places);
    } catch (_) {
      // The next change, or the next app start, hands them over again.
      sent = null;
    }
  }

  ref.listen<PlacesState>(
    placesNotifierProvider,
    (_, next) => send(next),
    fireImmediately: true,
  );
});

/// What the geofences read from a place; the rest of it changes nothing there.
String _keyOf(Place p) =>
    '${p.id}|${p.name}|${p.latitude}|${p.longitude}|${p.radiusM}';
