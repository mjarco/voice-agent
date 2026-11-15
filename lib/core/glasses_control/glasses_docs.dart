import 'package:voice_agent/core/models/agent_action.dart';

/// The documents voice-agent writes for the G2 glasses (workspace off-roadmap
/// task G4, its design note drafts/01-va-gn-contract.md; glass-native's
/// docs/wake-protocol.md): a wake in the markup v2 of glass-native, a card
/// and, for a meal, a screen of voice-agent's own under `va/` whose "Cofnij"
/// is a long press. glass-native checks a document before it shows it.
///
/// Texts said by the owner or named by the agent go in the screen's state and
/// are read as `${…}`, so a `${` or a quote in them stays text.
class GlassesDocs {
  GlassesDocs._();

  /// One document per action the glasses confirm, in the order of [actions].
  static List<Map<String, Object?>> ofActions(List<AgentAction> actions) => [
        for (final a in actions)
          switch (a.kind) {
            AgentActionKind.mealLogged => mealLogged(a),
            AgentActionKind.utteranceQueued => utteranceQueued(a),
          },
      ];

  /// A meal logged (V4): the card "Zjedzone: name", its kcal, time and what is
  /// left; a pick soon after opens its screen, where a long press on
  /// "Cofnij" removes the meal, as the phone's card does.
  static Map<String, Object?> mealLogged(AgentAction a) {
    final path = 'va/meal/${Uri.encodeComponent(a.mealId)}';
    final left = a.leftKcal == null ? '' : ' · zostało ${a.leftKcal} kcal';
    return {
      'version': 2,
      'card': {
        'id': 'va:meal:${a.mealId}',
        'title': 'Zjedzone: ${a.name}',
        'body': '${a.kcal} kcal · ${a.time}$left',
      },
      'open': path,
      'screens': {
        path: {
          'version': 2,
          'path': path,
          'use': 'rows',
          'title': 'Zjedzone',
          'state': {
            'undone': false,
            'meal': '${a.name} · ${a.time}',
            'kcal': '${a.kcal} kcal (${a.kcalLow}–${a.kcalHigh})',
            'left': a.leftKcal == null ? '' : 'Zostało ${a.leftKcal} kcal',
          },
          'rows': [
            {'label': r'${meal}'},
            {'label': r'${kcal}'},
            if (a.leftKcal != null) {'label': r'${left}'},
            {
              'label': r"${if(undone, 'Cofnięto', 'Cofnij: przytrzymaj')}",
              'on_hold': [
                {
                  'call': {'method': 'DELETE', 'path': '/api/v1/diet/meals/${Uri.encodeComponent(a.mealId)}'},
                  'when': 'not(undone)',
                },
                {'set': 'undone', 'to': 'true'},
              ],
            },
          ],
        },
      },
    };
  }

  /// An utterance put aside for the evening (V5): a card with the words as
  /// said; it is settled on the phone, in the evening, so it opens nothing.
  static Map<String, Object?> utteranceQueued(AgentAction a) => {
        'version': 2,
        'card': {
          'id': 'va:queued:${a.queuedId}',
          'title': 'Odłożone na wieczór',
          'body': a.said,
        },
      };
}
