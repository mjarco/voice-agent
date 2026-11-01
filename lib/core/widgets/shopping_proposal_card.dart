import 'package:flutter/material.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';

/// One proposal, on a thread and on the Shopping tab. It lives in `core/`
/// because features do not import each other (ADR-ARCH-003) and the other way
/// is the same card twice.
class ShoppingProposalCard extends StatelessWidget {
  const ShoppingProposalCard({
    super.key,
    required this.row,
    required this.onAccept,
    required this.onSkip,
  });

  final ShoppingProposalRow row;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  static const _ask = {'add': 'Add to shopping: ', 'bought': 'Tick off: '};
  static const _accept = {'add': 'Add', 'bought': 'Tick off'};
  static const _done = {'add': 'added', 'bought': 'ticked off'};

  String get _stateLabel {
    final proposal = row.proposal;
    return proposal.state == 'accepted'
        ? _done[proposal.kind] ?? proposal.state
        : proposal.state;
  }

  @override
  Widget build(BuildContext context) {
    final proposal = row.proposal;
    final theme = Theme.of(context);
    final note = row.note;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_ask[proposal.kind] ?? ''}${proposal.text}'),
            if (!proposal.isWaiting)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  _stateLabel,
                  key: Key('shopping-proposal-state-${proposal.id}'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  note,
                  key: Key('shopping-proposal-note-${proposal.id}'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (proposal.isWaiting)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('shopping-proposal-skip-${proposal.id}'),
                    onPressed: row.answering ? null : onSkip,
                    child: const Text('Skip'),
                  ),
                  if (row.canAccept) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      key: Key('shopping-proposal-accept-${proposal.id}'),
                      onPressed: row.answering ? null : onAccept,
                      child: Text(_accept[proposal.kind] ?? 'Accept'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
