import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';

class PlacesState {
  const PlacesState({
    this.loaded = false,
    this.places = const [],
    this.pendingPuts = const {},
    this.pendingDeletes = const {},
    this.storeTypes = const [],
    this.waitingForLink = false,
    this.error,
  });

  final bool loaded;
  final List<Place> places;
  final Set<String> pendingPuts;
  final Set<String> pendingDeletes;
  final List<PlaceStoreType> storeTypes;

  /// The last send found no link or no PA; it will try again by itself.
  final bool waitingForLink;

  /// PA refused something; it stays on the phone and is tried again.
  final String? error;

  int get pendingCount => pendingPuts.length + pendingDeletes.length;

  PlacesState copyWith({
    bool? loaded,
    List<Place>? places,
    Set<String>? pendingPuts,
    Set<String>? pendingDeletes,
    List<PlaceStoreType>? storeTypes,
    bool? waitingForLink,
    String? Function()? error,
  }) => PlacesState(
    loaded: loaded ?? this.loaded,
    places: places ?? this.places,
    pendingPuts: pendingPuts ?? this.pendingPuts,
    pendingDeletes: pendingDeletes ?? this.pendingDeletes,
    storeTypes: storeTypes ?? this.storeTypes,
    waitingForLink: waitingForLink ?? this.waitingForLink,
    error: error == null ? this.error : error(),
  );
}

/// The one owner of the local copy and the queue (ADR-NET-006). Every change is
/// written on the phone first and then sent, so saving needs no link.
class PlacesNotifier extends StateNotifier<PlacesState> {
  PlacesNotifier(this._repository, this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const PlacesState()) {
    _ready = _load();
  }

  /// A function, because the client changes with Settings and this does not.
  final PlacesRepository Function() _repository;
  final PlacesLocalStore _store;
  final DateTime Function() _now;

  late final Future<void> _ready;
  Future<void>? _running;
  bool _again = false;

  Future<void> _load() async {
    PlacesSnapshot snapshot;
    try {
      snapshot = await _store.load();
    } catch (_) {
      // A copy that cannot be read is rebuilt from PA.
      snapshot = const PlacesSnapshot();
    }
    if (!mounted) return;
    state = state.copyWith(
      loaded: true,
      places: _sorted(snapshot.places),
      pendingPuts: snapshot.pendingPuts,
      pendingDeletes: snapshot.pendingDeletes,
      storeTypes: snapshot.storeTypes,
    );
  }

  static List<Place> _sorted(List<Place> places) =>
      [...places]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _persist() async {
    if (!mounted) return;
    await _store.save(
      PlacesSnapshot(
        places: state.places,
        pendingPuts: state.pendingPuts,
        pendingDeletes: state.pendingDeletes,
        storeTypes: state.storeTypes,
      ),
    );
  }

  /// Saves a place on the phone, then sends it. A changed place gets a new time.
  Future<void> save(Place place) async {
    await _ready;
    final stamped = place.copyWith(updatedAt: _now().toUtc());
    state = state.copyWith(
      places: _sorted([
        for (final p in state.places)
          if (p.id != stamped.id) p,
        stamped,
      ]),
      pendingPuts: {...state.pendingPuts, stamped.id},
      pendingDeletes: {...state.pendingDeletes}..remove(stamped.id),
    );
    await _persist();
    unawaited(sync());
  }

  /// Removes a place on the phone, then sends that.
  Future<void> remove(String id) async {
    await _ready;
    state = state.copyWith(
      places: [
        for (final p in state.places)
          if (p.id != id) p,
      ],
      pendingPuts: {...state.pendingPuts}..remove(id),
      pendingDeletes: {...state.pendingDeletes, id},
    );
    await _persist();
    unawaited(sync());
  }

  /// Sends what waits and reads the list. One run at a time; a call during a
  /// run asks for one more, so a change made meanwhile is not left behind.
  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _syncUntilDone().whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  Future<void> _syncUntilDone() async {
    await _ready;
    do {
      _again = false;
      await _syncOnce();
    } while (_again && mounted);
  }

  Future<void> _syncOnce() async {
    final repository = _repository();
    String? refused;
    try {
      for (final id in {...state.pendingDeletes}) {
        try {
          await repository.delete(id);
          _deleted(id);
        } on PlacesException catch (e) {
          if (e.temporary) rethrow;
          refused = e.message;
        }
      }
      for (final id in {...state.pendingPuts}) {
        final place = _find(id);
        if (place == null) continue;
        try {
          _sent(place, await repository.put(place));
        } on PlacesException catch (e) {
          if (e.temporary) rethrow;
          refused = e.message;
        }
      }
      final places = await repository.fetchPlaces();
      final types = await repository.fetchStoreTypes();
      if (!mounted) return;
      state = state.copyWith(
        places: _sorted([
          for (final p in places)
            if (!state.pendingPuts.contains(p.id) &&
                !state.pendingDeletes.contains(p.id))
              p,
          ...state.places.where((p) => state.pendingPuts.contains(p.id)),
        ]),
        storeTypes: types,
        waitingForLink: false,
        error: () => refused,
      );
    } on PlacesException catch (e) {
      if (!mounted) return;
      state = e.temporary
          ? state.copyWith(waitingForLink: true, error: () => refused)
          : state.copyWith(waitingForLink: false, error: () => e.message);
    } catch (_) {
      // An answer that cannot be read: the copy stands, as with no link.
      if (!mounted) return;
      state = state.copyWith(waitingForLink: true, error: () => refused);
    }
    await _persist();
  }

  Place? _find(String id) {
    for (final p in state.places) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _deleted(String id) {
    if (!mounted) return;
    state = state.copyWith(
      pendingDeletes: {...state.pendingDeletes}..remove(id),
    );
  }

  /// Adopts PA's answer, unless the place changed again while it was sent.
  void _sent(Place sent, Place stored) {
    if (!mounted) return;
    // Each change is a new object, so two changes in the same instant differ.
    if (!identical(_find(sent.id), sent)) return;
    state = state.copyWith(
      places: _sorted([
        for (final p in state.places)
          if (p.id != stored.id) p,
        stored,
      ]),
      pendingPuts: {...state.pendingPuts}..remove(sent.id),
    );
  }
}
