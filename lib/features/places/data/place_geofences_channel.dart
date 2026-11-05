import 'package:flutter/services.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';

/// [PlaceGeofencesPort] over `com.voiceagent/place_geofences`. Kotlin keeps
/// the list, so the geofences can be registered again at boot without Flutter.
class PlaceGeofencesChannel implements PlaceGeofencesPort {
  PlaceGeofencesChannel({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.voiceagent/place_geofences');

  final MethodChannel _channel;

  @override
  Future<void> setPlaces(List<Place> places) =>
      _channel.invokeMethod('setPlaces', [
        for (final p in places)
          {
            'id': p.id,
            'name': p.name,
            'lat': p.latitude,
            'lon': p.longitude,
            'radius_m': p.radiusM,
          },
      ]);
}
