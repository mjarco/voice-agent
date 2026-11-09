import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_notifier.dart';
import 'package:voice_agent/features/matters/presentation/matters_notifier.dart';

import '../fake_matters_repository.dart';

const _active = MatterSummary(id: 'a', title: 'A', status: MatterStatus.active);
const _proposed =
    MatterSummary(id: 'p', title: 'P', status: MatterStatus.proposed);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('MattersNotifier', () {
    test('reads the proposed matters apart from the rest', () async {
      final notifier = MattersNotifier(
        FakeMattersRepository(matters: [_proposed, _active]),
      );
      await _settle();

      final state = notifier.state as MattersListLoaded;
      expect(state.proposed.map((m) => m.id), ['p']);
      expect(state.matters.map((m) => m.id), ['a']);
    });

    test('a failed drop keeps the list and records the message', () async {
      final repo = FakeMattersRepository(matters: [_proposed]);
      final notifier = MattersNotifier(repo);
      await _settle();
      repo.error = MatterRefusedException('not_proposed', 'już przyjęta');

      expect(await notifier.drop('p'), isFalse);
      expect(notifier.lastActionError, 'już przyjęta');
      expect((notifier.state as MattersListLoaded).proposed, hasLength(1));
    });
  });

  group('MatterDetailNotifier', () {
    late FakeMattersRepository repo;

    setUp(() {
      repo = FakeMattersRepository(details: {
        'a': const MatterDetail(matter: _active),
      });
    });

    test('a write shows the matter the server answered with', () async {
      final notifier = MatterDetailNotifier(repo, 'a');
      await _settle();

      expect(await notifier.setWaitingFor('wycena'), isTrue);
      final state = notifier.state as MatterDetailLoaded;
      expect(state.detail.matter.waitingFor, 'wycena');
    });

    test('an added entry is shown after the matter is read again', () async {
      final notifier = MatterDetailNotifier(repo, 'a');
      await _settle();
      final before = repo.fetches;

      expect(await notifier.addEntry('notatka'), isTrue);
      expect(repo.fetches, before + 1);
      final state = notifier.state as MatterDetailLoaded;
      expect(state.detail.timeline.single.text, 'notatka');
    });

    test('a failed write keeps the state and records the message', () async {
      final notifier = MatterDetailNotifier(repo, 'a');
      await _settle();
      repo.error = MattersGeneralException('offline');

      expect(await notifier.setStatus(MatterStatus.closed), isFalse);
      expect(notifier.lastActionError, 'offline');
      final state = notifier.state as MatterDetailLoaded;
      expect(state.detail.matter.status, MatterStatus.active);
    });

    test('a missing matter is gone for good', () async {
      final notifier = MatterDetailNotifier(repo, 'x');
      await _settle();
      expect((notifier.state as MatterDetailError).gone, isTrue);
    });
  });
}
