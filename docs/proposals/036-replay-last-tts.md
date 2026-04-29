# Proposal 036 — Replay Last TTS Reply (Client-Side)

## Status: Draft (seed)

## Origin

Production conversation `019dd85d-b27e-7b26-9d5c-6fff5a5b5495` on 2026-04-29:

- [42] user: "Powtórz, żeby coś przerwało."
  → [43] agent: "Nie rozumiem — co dokładnie mam powtórzyć?"
- [44] user: "Powtórz ostatnią wygenerowaną wiadomość."
  → [45] agent re-generates the long action-item list — text identical, but
  this is a fresh LLM call, costs tokens, and adds latency.

The user wanted to *re-hear* the previous reply. There is no need to
round-trip the backend.

## Problem

"Powtórz" is a common voice command in hands-free use. Today it is treated as
a chat turn → LLM call → TTS render. Three issues:

1. Latency: 2–4 s wait for an answer the device already has.
2. Cost: a re-generation costs the same as a fresh question.
3. Drift: nothing guarantees the regenerated text matches the original; the
   user hears something close-but-different.

## Approach — Client-Side Local Command

This is a voice-agent-only proposal. No backend change.

1. **T1 — TTS reply buffer**
   Voice-agent keeps the last 3 TTS-spoken messages in memory
   (`text + segments`, where segments are the `<lang>`-aware split from
   voice 030). LRU.
2. **T2 — Local-command interceptor**
   Before sending a transcribed utterance to `/api/v1/voice/transcript`, run a
   PL+EN regex match against:
   - "powtórz" / "jeszcze raz" / "powtórz ostatnią" / "repeat" / "say again"
   If matched and buffer non-empty: replay the most recent buffered message
   via the existing TTS service. Skip backend round-trip.
3. **T3 — UX confirmation**
   Visible toast "Powtarzam ostatnią odpowiedź" + haptic tick. If buffer is
   empty (cold start, first turn): toast "Brak wcześniejszej odpowiedzi" and
   fall through to backend.
4. **T4 — Edge cases**
   - "powtórz drugą ostatnią" / "powtórz przedostatnią" → index 1 in buffer.
   - "powtórz, że X" → not a replay, fall through to backend.

A new conversation reset (personal-agent P057 / voice 029 `reset_session`) clears the buffer.

### Acceptance criteria

- "powtórz" replays from buffer in < 200 ms with zero network calls.
- The replayed audio is byte-identical to the previously spoken audio (same
  segments, same voices, same `<lang>` handling).
- Buffer is cleared on conversation reset (see T4 above).

## Risk

Low — Tier 0. Voice-agent only. No backend contract change. No proposal
dependency.

## Effort

1 PR in voice-agent.

## Non-goals

- No server-side replay endpoint.
- No replay across devices.
- No "show me the last reply text" — that is the chat history screen, not
  this.
