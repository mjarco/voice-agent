import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/plan.dart';
import 'package:voice_agent/features/plan/domain/plan_repository.dart';
import 'package:voice_agent/features/plan/domain/plan_state.dart';
import 'package:voice_agent/features/plan/presentation/plan_notifier.dart';

class _MockRepository implements PlanRepository {
  PlanResponse? nextPlan;
  Exception? fetchError;
  Exception? actionError;

  int fetchCount = 0;
  String? lastDoneId;
  String? lastDismissId;
  String? lastConfirmId;
  String? lastEndorseId;

  @override
  Future<PlanResponse> fetchPlan() async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    return nextPlan ?? _emptyPlan();
  }

  @override
  Future<void> markDone(String id) async {
    lastDoneId = id;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> dismiss(String id) async {
    lastDismissId = id;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> confirm(String id) async {
    lastConfirmId = id;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> toggleEndorse(String id) async {
    lastEndorseId = id;
    if (actionError != null) throw actionError!;
  }
}

PlanResponse _emptyPlan() => PlanResponse(
      topics: const [],
      uncategorized: const [],
      rules: const [],
      rulesUncategorized: const [],
      completed: const [],
      completedUncategorized: const [],
      totalCount: 0,
      observedAt: DateTime(2026, 4, 18),
    );

PlanResponse _planWithEntry() => PlanResponse(
      topics: const [],
      uncategorized: [
        PlanEntry(
          entryId: 'e-1',
          displayText: 'Do thing',
          planBucket: PlanBucket.committed,
          confidence: 0.9,
          conversationId: 'conv-1',
          createdAt: DateTime(2026, 4, 18),
        ),
      ],
      rules: const [],
      rulesUncategorized: const [],
      completed: const [],
      completedUncategorized: const [],
      totalCount: 1,
      observedAt: DateTime(2026, 4, 18),
    );

void main() {
  late _MockRepository repo;

  setUp(() {
    repo = _MockRepository();
  });

  group('PlanNotifier', () {
    test('constructor calls load and transitions to PlanLoaded', () async {
      repo.nextPlan = _planWithEntry();
      final notifier = PlanNotifier(repo);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<PlanLoaded>());
      final loaded = notifier.state as PlanLoaded;
      expect(loaded.plan.uncategorized, hasLength(1));
    });

    test('transitions to PlanError on fetch failure', () async {
      repo.fetchError = Exception('Network error');
      final notifier = PlanNotifier(repo);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<PlanError>());
      expect(
        (notifier.state as PlanError).message,
        contains('Network error'),
      );
    });

    test('refresh reloads the plan', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      await notifier.refresh();

      expect(repo.fetchCount, 1);
      expect(notifier.state, isA<PlanLoaded>());
    });

    test('lastActionError clears on load', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanGeneralException('Some error');
      await notifier.markDone('e-1');
      expect(notifier.lastActionError, 'Some error');

      repo.actionError = null;
      await notifier.refresh();
      expect(notifier.lastActionError, isNull);
    });

    test('markDone returns true and reloads on success', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      final result = await notifier.markDone('e-1');

      expect(result, isTrue);
      expect(repo.lastDoneId, 'e-1');
      expect(repo.fetchCount, 1);
      expect(notifier.lastActionError, isNull);
    });

    test('markDone returns false on PlanGeneralException', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanGeneralException('Server error');
      final result = await notifier.markDone('e-1');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Server error');
    });

    test('markDone returns false on PlanConflictException', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanConflictException();
      final result = await notifier.markDone('e-1');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Action not available for this item');
    });

    test('dismiss returns true and reloads on success', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.dismiss('e-2');

      expect(result, isTrue);
      expect(repo.lastDismissId, 'e-2');
    });

    test('dismiss returns false on failure', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanGeneralException('Cannot dismiss');
      final result = await notifier.dismiss('e-2');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Cannot dismiss');
    });

    test('confirm returns true and reloads on success', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.confirm('e-3');

      expect(result, isTrue);
      expect(repo.lastConfirmId, 'e-3');
    });

    test('confirm returns false on PlanConflictException', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanConflictException();
      final result = await notifier.confirm('e-3');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Action not available for this item');
    });

    test('toggleEndorse returns true and reloads on success', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.toggleEndorse('e-4');

      expect(result, isTrue);
      expect(repo.lastEndorseId, 'e-4');
    });

    test('toggleEndorse returns false on failure', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanGeneralException('Cannot endorse');
      final result = await notifier.toggleEndorse('e-4');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Cannot endorse');
    });

    test('lastActionError clears before each action', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = PlanGeneralException('Error 1');
      await notifier.markDone('e-1');
      expect(notifier.lastActionError, 'Error 1');

      repo.actionError = null;
      await notifier.dismiss('e-2');
      expect(notifier.lastActionError, isNull);
    });

    test('failed action does not reload plan', () async {
      final notifier = PlanNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      repo.actionError = PlanConflictException();
      await notifier.markDone('e-1');

      expect(repo.fetchCount, 0);
    });
  });
}
