# ADR-NET-011: voice-agent writes documents for the glasses

Status: Accepted (on the branch of the redesign; merged with it)

## Context

glass-native draws the G2 glasses from personal-agent's markup v2. The owner asked that voice-agent
could write that markup too (workspace discussion `2026-11-gn-pa-contracts-review`, M8); the
workspace's off-roadmap task `2026-11-15-g4-glasses-va-author` built it, with its design note
`drafts/01-va-gn-contract.md`. A shop's arrival woke the glasses by naming a view glass-native then
asked personal-agent for, and what a voice turn did (a meal logged, V4; words put aside for the
evening, V5) showed only on the phone.

## Decision

1. **The intent SHOW carries `doc`**: a markup v2 wake (`card`, `open`, `screens` under `va/`),
   written by voice-agent; glass-native checks it before it shows anything (its
   `docs/wake-protocol.md`).
2. **A shop's arrival** (`GlassesWake`, Kotlin) sends the trigger's card leading to the store's
   checklist (`zakupy/<type>`, `zakupy` for several), with `view` and `params` beside it for an
   older glass-native.
3. **After a reply** of the sync worker (a voice turn), every action it carries goes to the glasses
   (`GlassesDocs`, Dart, through `GlassesControlPort.show`): a meal logged as the card "Zjedzone: …"
   whose screen undoes it with a long press on "Cofnij" (`DELETE /api/v1/diet/meals/{id}`, as the
   phone's card), an utterance queued (personal-agent ADR-API-131) as the card "Odłożone na wieczór".
4. Texts said by the owner go in a screen's state and are read as `${…}`.
5. **The sender shares its identity** (`BroadcastOptions.setShareIdentityEnabled`, Android 14+):
   glass-native takes a document whose screens call personal-agent only from voice-agent as the
   system names it, since the intent's permission is `normal`.

## Rationale

The trigger already carries the card's words, so no read of personal-agent stands before the card;
a confirmation needs what only the reply knows. A document of glass-native's markup keeps one
language for both authors, and glass-native's check is the guard.

## Consequences

- voice-agent and glass-native must point at the same personal-agent: a screen's calls go where
  glass-native is set.
- A typed turn (chat) sends nothing to the glasses; only the sync worker's replies do.
- Without glass-native the broadcast reaches no one; an older one ignores `doc`, and a confirmation
  (no `view`) is refused there.
