import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';
import 'package:voice_agent/features/places/presentation/places_notifier.dart';

import 'fakes.dart';

const _noLink = PlacesException('no link', temporary: true);

void main() {
  late FakePlacesRepository repository;
  late FakePlacesStore store;

  PlacesNotifier notifier() => PlacesNotifier(
    () => repository,
    store,
    now: () => DateTime.utc(2026, 11, 2, 12),
  );

  setUp(() {
    repository = FakePlacesRepository();
    store = FakePlacesStore();
  });

  test('a save with no link stays on the phone and arrives once', () async {
    repository.failure = _noLink;
    final first = notifier();
    await first.save(place('p1'));
    await first.sync();
    expect(first.state.places.single.id, 'p1');
    expect(first.state.pendingPuts, {'p1'});
    expect(first.state.waitingForLink, isTrue);
    expect(store.snapshot.pendingPuts, {'p1'});

    // The app was closed; a new run finds the queue.
    first.dispose();
    repository.failure = null;
    final second = notifier();
    await second.sync();
    expect(repository.puts, ['p1']);
    expect(second.state.pendingCount, 0);
    expect(second.state.places.single.id, 'p1');

    await second.sync();
    expect(repository.puts, ['p1']);
  });

  test('a refused place stays and does not stop the others', () async {
    repository
      ..failPutId = 'bad'
      ..failPutOf = const PlacesException('nope', temporary: false);
    final subject = notifier();
    await subject.save(place('bad'));
    await subject.save(place('good'));
    await subject.sync();
    expect(repository.puts, contains('good'));
    expect(subject.state.pendingPuts, {'bad'});
    expect(subject.state.places.map((p) => p.id), contains('bad'));
    expect(subject.state.error, 'nope');
  });

  test(
    'a read brings what the web UI changed and drops what it deleted',
    () async {
      final seeded = place('kept');
      store = FakePlacesStore(PlacesSnapshot(places: [seeded, place('gone')]));
      repository.server['kept'] = place('kept', name: 'Poprawione');
      final subject = notifier();
      await subject.sync();
      expect(subject.state.places.single.name, 'Poprawione');
      expect(subject.state.storeTypes.single.id, 'diy');
    },
  );

  test('a local change is not overwritten by a read', () async {
    repository.server['p1'] = place('p1', name: 'Stara');
    repository.failPutId = 'p1';
    repository.failPutOf = const PlacesException('later', temporary: false);
    final subject = notifier();
    await subject.save(place('p1', name: 'Nowa'));
    await subject.sync();
    expect(subject.state.places.single.name, 'Nowa');
  });

  test('a delete with no link goes out later', () async {
    repository.server['p1'] = place('p1');
    final subject = notifier();
    await subject.sync();
    repository.failure = _noLink;
    await subject.remove('p1');
    await subject.sync();
    expect(subject.state.places, isEmpty);
    expect(subject.state.pendingDeletes, {'p1'});

    repository.failure = null;
    await subject.sync();
    expect(repository.deletes, ['p1']);
    expect(subject.state.pendingCount, 0);
    expect(subject.state.places, isEmpty);
  });

  test('a delete drops a save still waiting', () async {
    repository.failure = _noLink;
    final subject = notifier();
    await subject.save(place('p1'));
    await subject.remove('p1');
    repository.failure = null;
    await subject.sync();
    expect(repository.puts, isEmpty);
  });

  test('a change made during a send is sent too', () async {
    final subject = notifier();
    var changed = false;
    repository.onPut = () {
      if (changed) return;
      changed = true;
      subject.save(place('p1', name: 'Druga'));
    };
    await subject.save(place('p1', name: 'Pierwsza'));
    await subject.sync();
    await pumpEventQueue();
    await subject.sync();
    expect(repository.server['p1']!.name, 'Druga');
    expect(subject.state.pendingCount, 0);
  });

  test('a save stamps the change with the time of the change', () async {
    final subject = notifier();
    await subject.save(place('p1'));
    await subject.sync();
    expect(repository.server['p1']!.updatedAt, DateTime.utc(2026, 11, 2, 12));
  });
}
