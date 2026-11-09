import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pins_notifier.dart';

class _MockRepository implements PinsRepository {
  List<PinSummary> pins;
  Exception? fetchError;
  Exception? unpinError;

  int fetchCount = 0;
  String? lastUnpinId;

  _MockRepository({this.pins = const []});

  @override
  Future<List<PinSummary>> fetchPins() async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    return pins;
  }

  @override
  Future<PinDetail> fetchPin(String recordId) async =>
      throw UnimplementedError();

  @override
  Future<void> unpin(String recordId) async {
    lastUnpinId = recordId;
    if (unpinError != null) throw unpinError!;
  }
}

PinSummary _pin(String id) => PinSummary(
      recordId: id,
      pinName: 'pin $id',
      createdAt: DateTime.utc(2026, 6, 15),
    );

void main() {
  test('loads pins on construction (initial -> loading -> loaded)', () async {
    final repo = _MockRepository(pins: [_pin('a'), _pin('b')]);
    final notifier = PinsNotifier(repo);

    expect(notifier.state, isA<PinsListLoading>());
    await Future<void>.delayed(Duration.zero);

    final state = notifier.state;
    expect(state, isA<PinsListLoaded>());
    expect((state as PinsListLoaded).pins, hasLength(2));
  });

  test('emits error when the fetch throws', () async {
    final repo = _MockRepository()..fetchError = Exception('boom');
    final notifier = PinsNotifier(repo);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state, isA<PinsListError>());
  });

  test('unpin success removes the row from the loaded list', () async {
    final repo = _MockRepository(pins: [_pin('a'), _pin('b')]);
    final notifier = PinsNotifier(repo);
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.unpin('a');

    expect(ok, isTrue);
    expect(repo.lastUnpinId, 'a');
    final pins = (notifier.state as PinsListLoaded).pins;
    expect(pins.map((p) => p.recordId), ['b']);
  });

  test('unpin failure keeps the list and records the error', () async {
    final repo = _MockRepository(pins: [_pin('a')])
      ..unpinError = PinsGeneralException('nope');
    final notifier = PinsNotifier(repo);
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.unpin('a');

    expect(ok, isFalse);
    expect(notifier.lastActionError, 'nope');
    expect((notifier.state as PinsListLoaded).pins, hasLength(1));
  });

  test('a stale unpin reads the list again and keeps the message', () async {
    final repo = _MockRepository(pins: [_pin('a')])
      ..unpinError = PinRefusedException('pin_changed', 'wczytaj ponownie');
    final notifier = PinsNotifier(repo);
    await Future<void>.delayed(Duration.zero);
    final countAfterLoad = repo.fetchCount;

    final ok = await notifier.unpin('a');

    expect(ok, isFalse);
    expect(repo.fetchCount, countAfterLoad + 1);
    expect(notifier.lastActionError, 'wczytaj ponownie');
    expect(notifier.state, isA<PinsListLoaded>());
  });
}
