import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_notifier.dart';

import '../fake_shopping_repository.dart';

void main() {
  late FakeShoppingRepository repository;

  setUp(() => repository = FakeShoppingRepository());

  Future<ShoppingNotifier> create({
    Duration delay = const Duration(hours: 1),
  }) async {
    final notifier = ShoppingNotifier(repository, rereadDelay: delay);
    await notifier.load();
    return notifier;
  }

  test('loads the list and the catalogue', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);

    final state = notifier.state as ShoppingLoaded;
    expect(state.items.single.text, 'kabel HDMI');
    expect(state.catalogue.total, 1);
    expect(state.view, ShoppingView.toBuy);
    expect(state.filter, isNull);
  });

  test('a first failed read is an error, Retry reads again', () async {
    repository.nextReadError = ShoppingGeneralException('no route');
    final notifier = await create();
    addTearDown(notifier.dispose);
    expect(notifier.state, isA<ShoppingError>());

    repository.nextReadError = null;
    await notifier.retry();

    expect(notifier.state, isA<ShoppingLoaded>());
  });

  test('a later failed read leaves the list in place', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);

    repository.nextReadError = ShoppingGeneralException('no route');
    await notifier.load();

    expect(notifier.state, isA<ShoppingLoaded>());
  });

  test('a new selection shows at once and reads its list', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);

    final read = notifier.selectFilter('electrical');
    expect((notifier.state as ShoppingLoaded).filter, 'electrical');
    await read;

    expect(repository.lastStoreType, 'electrical');
  });

  test('a new selection does not pass the old list off as its own', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);

    final read = notifier.selectView(ShoppingView.bought);
    expect((notifier.state as ShoppingLoaded).reading, isTrue);
    await read;

    final state = notifier.state as ShoppingLoaded;
    expect(state.reading, isFalse);
    expect(state.items, isEmpty);
  });

  test('a failed read of a new selection says so, Retry reads it', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);
    repository.nextReadError = ShoppingGeneralException('no route');

    await notifier.selectView(ShoppingView.bought);

    var state = notifier.state as ShoppingLoaded;
    expect(state.view, ShoppingView.bought);
    expect(state.reading, isFalse);
    expect(state.readError, contains('no route'));

    repository.nextReadError = null;
    await notifier.retry();

    state = notifier.state as ShoppingLoaded;
    expect(state.readError, isNull);
    expect(repository.lastView, ShoppingView.bought);
  });

  test('a stale answer does not overwrite a newer selection', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);

    await Future.wait([
      notifier.selectView(ShoppingView.bought),
      notifier.selectView(ShoppingView.toBuy),
    ]);

    expect((notifier.state as ShoppingLoaded).view, ShoppingView.toBuy);
  });

  test('a saved item being tagged is read again after the delay', () async {
    final notifier = await create(delay: const Duration(milliseconds: 10));
    addTearDown(notifier.dispose);
    final reads = repository.reads;

    await notifier.add('mleko');
    expect(repository.reads, reads + 1);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.reads, reads + 2);
  });

  test('an item saved with types is not read again', () async {
    final notifier = await create(delay: const Duration(milliseconds: 10));
    addTearDown(notifier.dispose);
    final reads = repository.reads;

    await notifier.add('mleko', storeTypes: ['grocery']);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.reads, reads + 1);
    expect(repository.lastAddTypes, ['grocery']);
  });

  test('a later save restarts the re-read', () async {
    final notifier = await create(delay: const Duration(milliseconds: 40));
    addTearDown(notifier.dispose);
    final reads = repository.reads;

    await notifier.add('mleko');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await notifier.add('chleb');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(repository.reads, reads + 2);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(repository.reads, reads + 3);
  });

  test('the same text says it is already on the list', () async {
    repository.nextAdd = ShoppingAddResult(item: sampleItem(), created: false);
    final notifier = await create();
    addTearDown(notifier.dispose);

    expect(
      await notifier.add('kabel HDMI'),
      ShoppingAddOutcome.alreadyOnList,
    );
  });

  test('an item outside the view says so', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);

    expect(await notifier.add('mleko'), ShoppingAddOutcome.added);

    await notifier.selectFilter('electrical');
    expect(await notifier.add('chleb'), ShoppingAddOutcome.addedNotShown);

    await notifier.selectFilter('other');
    expect(await notifier.add('sól'), ShoppingAddOutcome.added);

    await notifier.selectFilter(null);
    await notifier.selectView(ShoppingView.bought);
    expect(await notifier.add('cukier'), ShoppingAddOutcome.addedNotShown);
  });

  test('a failed save reports the error and keeps the state', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);
    repository.nextWriteError = ShoppingGeneralException('no route');

    expect(await notifier.add('mleko'), ShoppingAddOutcome.failed);

    expect(notifier.lastActionError, 'no route');
    expect(notifier.state, isA<ShoppingLoaded>());
  });

  test('ticking off sends the active filter', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);
    await notifier.selectFilter('electrical');

    expect(await notifier.markBought('i1'), isTrue);

    expect(repository.lastBoughtStoreType, 'electrical');
  });

  test('a conflict is reported', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);
    repository.nextWriteError = ShoppingConflictException();

    expect(await notifier.markBought('i1'), isFalse);

    expect(notifier.lastActionError, 'This item was removed');
  });

  test('a failed action reads the list again', () async {
    final notifier = await create();
    addTearDown(notifier.dispose);
    repository
      ..toBuy = []
      ..nextWriteError = ShoppingConflictException();

    expect(await notifier.markBought('i1'), isFalse);
    await pumpEventQueue();

    expect((notifier.state as ShoppingLoaded).items, isEmpty);
    expect(notifier.lastActionError, 'This item was removed');
  });

  test('restoring an untagged item reads again after the delay', () async {
    repository.nextRestore = sampleItem(storeTypes: [], typesSource: null);
    final notifier = await create(delay: const Duration(milliseconds: 10));
    addTearDown(notifier.dispose);
    final reads = repository.reads;

    await notifier.restore('i1');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.reads, reads + 2);
  });
}
