import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/widgets/shopping_proposal_card.dart';

import '../network/fake_shopping_proposals.dart';

void main() {
  var accepts = 0;
  var skips = 0;

  setUp(() {
    accepts = 0;
    skips = 0;
  });

  Future<void> pump(WidgetTester tester, ShoppingProposalRow row) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ShoppingProposalCard(
          row: row,
          onAccept: () => accepts++,
          onSkip: () => skips++,
        ),
      ),
    ));
  }

  const accept = Key('shopping-proposal-accept-p1');
  const skip = Key('shopping-proposal-skip-p1');

  testWidgets('an add offers Add and Skip', (tester) async {
    await pump(tester, ShoppingProposalRow(sampleProposal()));

    expect(find.text('Add to shopping: filtr do wody'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.byKey(accept));
    await tester.tap(find.byKey(skip));

    expect(accepts, 1);
    expect(skips, 1);
  });

  testWidgets('a purchase offers Tick off', (tester) async {
    await pump(tester, ShoppingProposalRow(sampleProposal(kind: 'bought')));

    expect(find.text('Tick off: filtr do wody'), findsOneWidget);
    expect(find.text('Tick off'), findsOneWidget);
  });

  for (final (kind, state, label) in [
    ('add', 'accepted', 'added'),
    ('bought', 'accepted', 'ticked off'),
    ('add', 'skipped', 'skipped'),
    ('add', 'expired', 'expired'),
  ]) {
    testWidgets('$kind $state shows "$label" without buttons', (tester) async {
      await pump(
        tester,
        ShoppingProposalRow(sampleProposal(kind: kind, state: state)),
      );

      expect(find.text(label), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  }

  testWidgets('an answer on its way turns the buttons off', (tester) async {
    await pump(tester, ShoppingProposalRow(sampleProposal()).asAnswering());

    expect(tester.widget<TextButton>(find.byKey(skip)).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(accept)).onPressed, isNull);
  });

  testWidgets('an item gone leaves only Skip, with the reason', (tester) async {
    await pump(
      tester,
      ShoppingProposalRow(sampleProposal(kind: 'bought'))
          .after(const ProposalItemRemoved()),
    );

    expect(find.text('This item is no longer on the list'), findsOneWidget);
    expect(find.byKey(accept), findsNothing);
    expect(find.byKey(skip), findsOneWidget);
  });
}
