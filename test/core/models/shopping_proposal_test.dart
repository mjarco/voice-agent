import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';

import '../network/fake_shopping_proposals.dart';

void main() {
  test('reads the contract fields', () {
    final proposal = ShoppingProposal.fromMap({
      'id': 'p1',
      'kind': 'bought',
      'text': 'mleko',
      'state': 'accepted',
      'conversation_id': 'c1',
      'user_event_id': 'u1',
      'item_id': 'i1',
      'created_at': '2026-11-01T12:00:00Z',
      'resolved_at': '2026-11-01T12:05:00Z',
    });

    expect(proposal.id, 'p1');
    expect(proposal.kind, 'bought');
    expect(proposal.text, 'mleko');
    expect(proposal.isWaiting, isFalse);
    expect(proposal.userEventId, 'u1');
  });

  group('settled', () {
    test('an answer from any client settles it', () {
      expect(ProposalAnswered(sampleProposal()).settled, isTrue);
      expect(const ProposalNotWaiting('skipped').settled, isTrue);
    });

    test('a refusal or a failure does not', () {
      expect(const ProposalItemRemoved().settled, isFalse);
      expect(const ProposalAnswerFailed('x').settled, isFalse);
    });
  });

  group('after', () {
    final row = ShoppingProposalRow(sampleProposal()).asAnswering();

    test('an answered proposal replaces the row', () {
      final after = row.after(
        ProposalAnswered(sampleProposal().withState('accepted')),
      );

      expect(after.proposal.state, 'accepted');
      expect(after.answering, isFalse);
    });

    test('answered elsewhere takes the state from the conflict', () {
      final after = row.after(const ProposalNotWaiting('expired'));

      expect(after.proposal.state, 'expired');
      expect(after.note, isNull);
    });

    test('an item gone keeps it waiting, without accept', () {
      final after = row.after(const ProposalItemRemoved());

      expect(after.proposal.isWaiting, isTrue);
      expect(after.canAccept, isFalse);
      expect(after.answering, isFalse);
      expect(after.note, isNotNull);
    });

    test('a failure keeps accept off once the item is gone', () {
      final gone = row.after(const ProposalItemRemoved());

      final after = gone.after(const ProposalAnswerFailed('no route'));

      expect(after.note, 'Failed: no route');
      expect(after.canAccept, isFalse);
    });
  });

  group('fromRead', () {
    test('a waiting proposal keeps what its card shows', () {
      final previous = [
        ShoppingProposalRow(sampleProposal())
            .after(const ProposalItemRemoved()),
      ];

      final rows = ShoppingProposalRow.fromRead([sampleProposal()], previous);

      expect(rows.single.canAccept, isFalse);
      expect(rows.single.note, isNotNull);
    });

    test('an answer on its way stays on', () {
      final previous = [ShoppingProposalRow(sampleProposal()).asAnswering()];

      final rows = ShoppingProposalRow.fromRead([sampleProposal()], previous);

      expect(rows.single.answering, isTrue);
    });

    test('an answered proposal drops the marks', () {
      final previous = [
        ShoppingProposalRow(sampleProposal())
            .after(const ProposalItemRemoved()),
      ];

      final rows = ShoppingProposalRow.fromRead(
        [sampleProposal().withState('skipped')],
        previous,
      );

      expect(rows.single.note, isNull);
      expect(rows.single.answering, isFalse);
    });
  });
}
