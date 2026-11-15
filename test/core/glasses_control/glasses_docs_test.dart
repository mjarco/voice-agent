import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/glasses_control/glasses_docs.dart';
import 'package:voice_agent/core/models/agent_action.dart';

/// The documents voice-agent hands glass-native (G4). The goldens are what
/// glass-native's contract test reads (its core/src/test/resources/va-contract,
/// copied with SOURCE naming the commit); UPDATE_GOLDEN=1 writes them.
void main() {
  const meal = AgentAction.mealLogged(
    mealId: '01a1-meal',
    name: r"Kawa z mlekiem ${x} 'o'",
    day: '2026-11-15',
    time: '16:28',
    kcal: 50,
    kcalLow: 20,
    kcalHigh: 100,
    leftKcal: 320,
  );
  const queued = AgentAction.utteranceQueued(queuedId: 'q-1', said: 'może mleko');

  void golden(String name, Map<String, Object?> doc) {
    final file = File('test/core/glasses_control/goldens/$name.json');
    final text = '${const JsonEncoder.withIndent(' ').convert(doc)}\n';
    if (Platform.environment['UPDATE_GOLDEN'] == '1') file.writeAsStringSync(text);
    expect(text, file.readAsStringSync(), reason: '$name differs (UPDATE_GOLDEN=1 writes it)');
  }

  test('a meal: its card, its screen under va/, Cofnij by a long press', () {
    final d = GlassesDocs.mealLogged(meal);
    final card = d['card']! as Map;
    expect(card['title'], r"Zjedzone: Kawa z mlekiem ${x} 'o'");
    expect(card['body'], '50 kcal · 16:28 · zostało 320 kcal');
    expect(d['open'], 'va/meal/01a1-meal');
    final screen = (d['screens']! as Map)['va/meal/01a1-meal'] as Map;
    expect(screen['path'], d['open']);
    // The owner's words are in the state, read as ${…}, never in an expression.
    expect((screen['state']! as Map)['meal'], r"Kawa z mlekiem ${x} 'o' · 16:28");
    final undo = (screen['rows']! as List).last as Map;
    final hold = undo['on_hold']! as List;
    expect((hold.first as Map)['call'], {'method': 'DELETE', 'path': '/api/v1/diet/meals/01a1-meal'});
    expect((hold.first as Map)['when'], 'not(undone)');
    golden('meal', d);
  });

  test('a meal without a target has no line of what is left', () {
    const noTarget = AgentAction.mealLogged(
        mealId: 'm2', name: 'Jabłko', day: '2026-11-15', time: '10:00', kcal: 80, kcalLow: 60, kcalHigh: 100);
    final d = GlassesDocs.mealLogged(noTarget);
    expect((d['card']! as Map)['body'], '80 kcal · 10:00');
    expect(((d['screens']! as Map)['va/meal/m2'] as Map)['rows'], hasLength(3));
  });

  test('a queued utterance: a card with the words, opening nothing', () {
    final d = GlassesDocs.utteranceQueued(queued);
    expect(d['card'], {'id': 'va:queued:q-1', 'title': 'Odłożone na wieczór', 'body': 'może mleko'});
    expect(d.containsKey('open'), isFalse);
    golden('queued', d);
  });

  test('one document per action, in order', () {
    expect(GlassesDocs.ofActions(const [meal, queued]).map((d) => (d['card']! as Map)['id']),
        ['va:meal:01a1-meal', 'va:queued:q-1']);
  });

  test('a reply carries a queued utterance', () {
    final a = AgentAction.listFrom([
      {'kind': 'utterance_queued', 'queued': {'id': 'q-9', 'said': 'może'}},
      {'kind': 'other'},
      {'kind': 'utterance_queued', 'queued': {'id': 7}},
    ]);
    expect(a, hasLength(1));
    expect(a.single.kind, AgentActionKind.utteranceQueued);
    expect(a.single.queuedId, 'q-9');
    expect(a.single.said, 'może');
  });
}
