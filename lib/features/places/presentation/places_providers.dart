import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/places/data/api_places_repository.dart';
import 'package:voice_agent/features/places/data/place_geofences_channel.dart';
import 'package:voice_agent/features/places/data/place_reading_channel.dart';
import 'package:voice_agent/features/places/data/prefs_places_store.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';
import 'package:voice_agent/features/places/presentation/places_notifier.dart';

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => ApiPlacesRepository(ref.watch(apiClientProvider)),
);

final placesLocalStoreProvider = Provider<PlacesLocalStore>(
  (ref) => PrefsPlacesStore(),
);

final placeReadingPortProvider = Provider<PlaceReadingPort>(
  (ref) => PlaceReadingChannel(),
);

final placeGeofencesPortProvider = Provider<PlaceGeofencesPort>(
  (ref) => PlaceGeofencesChannel(),
);

/// Geofences exist on Android only; iOS is outside this stage.
final placeGeofencesAvailableProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
);

final placesNotifierProvider =
    StateNotifierProvider<PlacesNotifier, PlacesState>((ref) {
      return PlacesNotifier(
        () => ref.read(placesRepositoryProvider),
        ref.watch(placesLocalStoreProvider),
      );
    });
