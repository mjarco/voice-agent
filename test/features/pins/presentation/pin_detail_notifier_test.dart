import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_notifier.dart';

class _MockRepository implements PinsRepository {
  PinDetail? pin;
  Exception? fetchError;
  Exception? unpinError;

  String? lastFetchId;
  String? lastUnpinId;

  @override
  Future<List<PinSummary>> fetchPins(PinView view) async =>
      throw UnimplementedError();

  @override
  Future<PinDetail> fetchPin(String recordId) async {
    lastFetchId = recordId;
    if (fetchError != null) throw fetchError!;
    return pin ?? _detail(recordId);
  }

  @override
  Future<void> unpin(String recordId) async {
    lastUnpinId = recordId;
    if (unpinError != null) throw unpinError!;
  }
}

PinDetail _detail(String id) => PinDetail(
      recordId: id,
      pinName: 'pin $id',
      text: '# Body',
      createdAt: DateTime.utc(2026, 6, 15),
    );

void main() {
  test('loads the pin on construction', () async {
    final repo = _MockRepository()..pin = _detail('abc');
    final notifier = PinDetailNotifier(repo, 'abc');

    expect(notifier.state, isA<PinDetailLoading>());
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state, isA<PinDetailLoaded>());
    expect((notifier.state as PinDetailLoaded).pin.text, '# Body');
    expect(repo.lastFetchId, 'abc');
  });

  test('emits error when the fetch throws', () async {
    final repo = _MockRepository()..fetchError = PinNotFoundException();
    final notifier = PinDetailNotifier(repo, 'missing');
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state, isA<PinDetailError>());
  });

  test('unpin success returns true', () async {
    final repo = _MockRepository()..pin = _detail('abc');
    final notifier = PinDetailNotifier(repo, 'abc');
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.unpin();

    expect(ok, isTrue);
    expect(repo.lastUnpinId, 'abc');
  });

  test('unpin failure returns false and records the error', () async {
    final repo = _MockRepository()
      ..pin = _detail('abc')
      ..unpinError = PinsGeneralException('nope');
    final notifier = PinDetailNotifier(repo, 'abc');
    await Future<void>.delayed(Duration.zero);

    final ok = await notifier.unpin();

    expect(ok, isFalse);
    expect(notifier.lastActionError, 'nope');
  });
}
