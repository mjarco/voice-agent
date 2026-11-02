import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/presentation/places_notifier.dart';
import 'package:voice_agent/features/places/presentation/places_providers.dart';

/// Suggestions only: a tag is free text.
const _suggestedTags = ['sklep', 'centrum handlowe', 'centrum usługowe'];

/// Above this the screen says the position may land off the place.
const _poorAccuracyM = 100.0;

List<String> _parseTags(String raw, Set<String> chosen) => {
  ...chosen,
  ...raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
}.toList();

/// Names where you stand, and lists the places. Reached from the Shopping and
/// Record app bars.
class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  final _name = TextEditingController();
  final _otherTags = TextEditingController();
  final _tags = <String>{};
  final _types = <String>{};

  PlaceReadingResult? _reading;
  bool _readingNow = false;
  bool _saving = false;

  /// You may have moved while the app was away, so a reading from before must
  /// not be saved as "here".
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_read()));
    _name.addListener(() => setState(() {}));
    unawaited(_read());
    unawaited(ref.read(placesNotifierProvider.notifier).sync());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _name.dispose();
    _otherTags.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (_readingNow) return;
    setState(() => _readingNow = true);
    final result = await ref.read(placeReadingPortProvider).read();
    if (!mounted) return;
    setState(() {
      _reading = result;
      _readingNow = false;
    });
  }

  Future<void> _save(PlaceReading reading) async {
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    try {
      await ref
          .read(placesNotifierProvider.notifier)
          .save(
            Place(
              id: const Uuid().v4(),
              name: _name.text.trim(),
              latitude: reading.latitude,
              longitude: reading.longitude,
              accuracyM: reading.accuracyM,
              radiusM: Place.defaultRadiusM,
              tags: _parseTags(_otherTags.text, _tags),
              storeTypes: _types.toList(),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    setState(() {
      _name.clear();
      _otherTags.clear();
      _tags.clear();
      _types.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(placesNotifierProvider);
    final reading = _reading?.reading;
    final canSave =
        reading != null &&
        !_readingNow &&
        !_saving &&
        _name.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Miejsca')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(placesNotifierProvider.notifier).sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _ReadingCard(
              result: _reading,
              reading: _readingNow,
              onRefresh: _read,
              onSettings: () =>
                  ref.read(placeReadingPortProvider).openSettings(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('places-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Nazwa tego miejsca',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            _TagChips(chosen: _tags, onChanged: () => setState(() {})),
            ExpansionTile(
              key: const Key('places-more'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Więcej: tagi i typy sklepu'),
              children: [
                TextField(
                  key: const Key('places-other-tags'),
                  controller: _otherTags,
                  decoration: const InputDecoration(
                    labelText: 'Inne tagi, po przecinku',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                _TypeChips(
                  types: state.storeTypes,
                  chosen: _types,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('places-save'),
              onPressed: canSave ? () => _save(reading) : null,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Zapisz tutaj'),
            ),
            _SyncLine(state: state),
            const SizedBox(height: 8),
            if (state.loaded && state.places.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nie ma jeszcze miejsc. Nazwij to, w którym stoisz.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final place in state.places)
              _PlaceTile(
                place: place,
                types: state.storeTypes,
                pending: state.pendingPuts.contains(place.id),
                onTap: () => _edit(place),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Place place) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PlaceEditor(place: place),
  );
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.result,
    required this.reading,
    required this.onRefresh,
    required this.onSettings,
  });

  final PlaceReadingResult? result;
  final bool reading;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  String _text() {
    final found = result?.reading;
    if (found != null) {
      final accuracy = found.accuracyM == null
          ? 'dokładność nieznana'
          : '±${found.accuracyM!.round()} m';
      final age = found.age.inMinutes >= 1
          ? ', sprzed ${found.age.inMinutes} min'
          : '';
      return '${found.latitude.toStringAsFixed(5)}, '
          '${found.longitude.toStringAsFixed(5)}\n$accuracy$age';
    }
    return switch (result?.problem) {
      PlaceReadingProblem.permission => 'Brak zgody na lokalizację',
      PlaceReadingProblem.noFix =>
        'Nie ma odczytu: włącz lokalizację albo podejdź bliżej okna',
      PlaceReadingProblem.unavailable => 'Na tym telefonie nie ma odczytu',
      null => 'Szukam pozycji…',
    };
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = result?.reading?.accuracyM;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_text(), key: const Key('places-reading')),
                  if (accuracy != null && accuracy > _poorAccuracyM)
                    Text(
                      'Słaba dokładność: można zapisać i poprawić później.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (result?.problem == PlaceReadingProblem.permission)
                    TextButton(
                      onPressed: onSettings,
                      child: const Text('Otwórz ustawienia'),
                    ),
                ],
              ),
            ),
            reading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: const Key('places-read-again'),
                    icon: const Icon(Icons.my_location),
                    tooltip: 'Odczytaj jeszcze raz',
                    onPressed: onRefresh,
                  ),
          ],
        ),
      ),
    );
  }
}

class _TagChips extends StatelessWidget {
  const _TagChips({required this.chosen, required this.onChanged});

  final Set<String> chosen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        for (final tag in {..._suggestedTags, ...chosen})
          FilterChip(
            label: Text(tag),
            selected: chosen.contains(tag),
            onSelected: (on) {
              on ? chosen.add(tag) : chosen.remove(tag);
              onChanged();
            },
          ),
      ],
    );
  }
}

class _TypeChips extends StatelessWidget {
  const _TypeChips({
    required this.types,
    required this.chosen,
    required this.onChanged,
  });

  final List<PlaceStoreType> types;
  final Set<String> chosen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return const Text('Typy sklepu pojawią się po połączeniu z PA.');
    }
    return Wrap(
      spacing: 6,
      children: [
        for (final type in types)
          FilterChip(
            key: Key('places-type-${type.id}'),
            label: Text(type.label),
            selected: chosen.contains(type.id),
            onSelected: (on) {
              on ? chosen.add(type.id) : chosen.remove(type.id);
              onChanged();
            },
          ),
      ],
    );
  }
}

class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.state});

  final PlacesState state;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (state.pendingCount > 0) 'Czeka na wysłanie: ${state.pendingCount}',
      if (state.error != null) 'PA odmówił: ${state.error}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(lines.join('\n'), key: const Key('places-sync-line')),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.place,
    required this.types,
    required this.pending,
    required this.onTap,
  });

  final Place place;
  final List<PlaceStoreType> types;
  final bool pending;
  final VoidCallback onTap;

  String _label(String id) {
    for (final type in types) {
      if (type.id == id) return type.label;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final details = [...place.storeTypes.map(_label), ...place.tags];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(place.name),
      subtitle: details.isEmpty ? null : Text(details.join(', ')),
      trailing: pending
          ? const Icon(Icons.cloud_upload_outlined, semanticLabel: 'Czeka')
          : null,
      onTap: onTap,
    );
  }
}

/// Renames, retags, moves to where you stand, or deletes.
class _PlaceEditor extends ConsumerStatefulWidget {
  const _PlaceEditor({required this.place});

  final Place place;

  @override
  ConsumerState<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends ConsumerState<_PlaceEditor> {
  late final _name = TextEditingController(text: widget.place.name);
  late final _tags = TextEditingController(text: widget.place.tags.join(', '));
  late final _types = {...widget.place.storeTypes};
  PlaceReading? _movedTo;
  bool _moving = false;
  String? _moveProblem;

  @override
  void dispose() {
    _name.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _moveHere() async {
    setState(() {
      _moving = true;
      _moveProblem = null;
    });
    final result = await ref.read(placeReadingPortProvider).read();
    if (!mounted) return;
    setState(() {
      _moving = false;
      _movedTo = result.reading ?? _movedTo;
      if (result.reading == null) _moveProblem = 'Nie ma odczytu.';
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final moved = _movedTo;
    final edited = widget.place.copyWith(
      name: name,
      tags: _parseTags(_tags.text, const {}),
      storeTypes: _types.toList(),
    );
    await ref
        .read(placesNotifierProvider.notifier)
        .save(moved == null ? edited : edited.movedTo(moved));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć to miejsce?'),
        content: Text(widget.place.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            key: const Key('places-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(placesNotifierProvider.notifier).remove(widget.place.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(placesNotifierProvider).storeTypes;
    final moved = _movedTo;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('places-edit-name'),
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Nazwa',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('places-edit-tags'),
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tagi, po przecinku',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _TypeChips(
              types: types,
              chosen: _types,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('places-move-here'),
              onPressed: _moving ? null : _moveHere,
              icon: const Icon(Icons.my_location),
              label: Text(
                moved == null
                    ? 'Przenieś tutaj'
                    : 'Nowa pozycja: ${moved.latitude.toStringAsFixed(5)}, '
                          '${moved.longitude.toStringAsFixed(5)}',
              ),
            ),
            if (_moveProblem != null) Text(_moveProblem!),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  key: const Key('places-delete'),
                  onPressed: _delete,
                  child: const Text('Usuń'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('places-edit-save'),
                  onPressed: _save,
                  child: const Text('Zapisz'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
