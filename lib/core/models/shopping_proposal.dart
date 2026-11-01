/// A purchase said in a conversation, offered and not yet done (personal-agent
/// ADR-API-108). Shared by chat and Shopping, so it lives in `core/`.
class ShoppingProposal {
  const ShoppingProposal({
    required this.id,
    required this.kind,
    required this.text,
    required this.state,
    this.userEventId,
  });

  final String id;

  /// `add` or `bought`.
  final String kind;
  final String text;

  /// `waiting`, `accepted`, `skipped` or `expired`.
  final String state;

  /// The user message that proposed it; a chat card is placed by this.
  final String? userEventId;

  bool get isWaiting => state == 'waiting';

  ShoppingProposal withState(String newState) => ShoppingProposal(
        id: id,
        kind: kind,
        text: text,
        state: newState,
        userEventId: userEventId,
      );

  factory ShoppingProposal.fromMap(Map<String, dynamic> map) {
    return ShoppingProposal(
      id: map['id'] as String,
      kind: map['kind'] as String,
      text: map['text'] as String,
      state: map['state'] as String,
      userEventId: map['user_event_id'] as String?,
    );
  }
}

/// What came of an answer. Only a broken connection or a server fault is a
/// failure; the two conflicts are outcomes the card has to show.
sealed class ShoppingProposalAnswer {
  const ShoppingProposalAnswer();

  /// The proposal is answered, by this client or another one, so the list and
  /// the waiting proposals may have changed.
  bool get settled => switch (this) {
        ProposalAnswered() || ProposalNotWaiting() => true,
        ProposalItemRemoved() || ProposalAnswerFailed() => false,
      };
}

class ProposalAnswered extends ShoppingProposalAnswer {
  const ProposalAnswered(this.proposal);
  final ShoppingProposal proposal;
}

/// `409 proposal_not_waiting`: another client answered first; [state] is how.
class ProposalNotWaiting extends ShoppingProposalAnswer {
  const ProposalNotWaiting(this.state);
  final String state;
}

/// `409 item_removed`: the item to tick off is gone. The proposal stays waiting
/// and can only be skipped.
class ProposalItemRemoved extends ShoppingProposalAnswer {
  const ProposalItemRemoved();
}

class ProposalAnswerFailed extends ShoppingProposalAnswer {
  const ProposalAnswerFailed(this.message);
  final String message;
}

/// A proposal as a card shows it: the proposal and what answering it left.
class ShoppingProposalRow {
  const ShoppingProposalRow(
    this.proposal, {
    this.answering = false,
    this.note,
    this.canAccept = true,
  });

  final ShoppingProposal proposal;

  /// An answer is on its way; the buttons are off.
  final bool answering;

  /// What the last answer ran into.
  final String? note;

  /// False once the item to tick off is gone.
  final bool canAccept;

  ShoppingProposalRow asAnswering() => ShoppingProposalRow(
        proposal,
        answering: true,
        note: note,
        canAccept: canAccept,
      );

  ShoppingProposalRow after(ShoppingProposalAnswer answer) => switch (answer) {
        ProposalAnswered(proposal: final answered) =>
          ShoppingProposalRow(answered),
        ProposalNotWaiting(state: final state) =>
          ShoppingProposalRow(proposal.withState(state)),
        ProposalItemRemoved() => ShoppingProposalRow(
            proposal,
            note: 'This item is no longer on the list',
            canAccept: false,
          ),
        ProposalAnswerFailed(message: final message) => ShoppingProposalRow(
            proposal,
            note: 'Failed: $message',
            canAccept: canAccept,
          ),
      };

  /// Rows for a fresh read. One still waiting keeps what the card shows about
  /// it: an answer on its way, or why the last one did not go through.
  static List<ShoppingProposalRow> fromRead(
    List<ShoppingProposal> read,
    List<ShoppingProposalRow> previous,
  ) {
    final byId = {for (final row in previous) row.proposal.id: row};
    return [
      for (final proposal in read)
        ShoppingProposalRow(
          proposal,
          answering: proposal.isWaiting && (byId[proposal.id]?.answering ?? false),
          note: proposal.isWaiting ? byId[proposal.id]?.note : null,
          canAccept: !proposal.isWaiting || (byId[proposal.id]?.canAccept ?? true),
        ),
    ];
  }
}
