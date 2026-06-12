# Proposal 043 — Envelope-tolerant agent-reply reader

## Status: Implemented (2026-06-10, PR #327) — device install done 2026-06-12 (stable flavor, Michal iPhone); personal-agent P088 envelope deployed to prod the same day. Tier 3 (personal-agent API contract change). Sibling of personal-agent P088.

## Problem

personal-agent P088 (proposal merged and Accepted in that repo —
`docs/proposals/P088-voice-transcript-envelope.md`; the server change
itself is **not yet implemented**, `voice.go` still serves the flat
shape) will wrap the `POST /api/v1/voice/transcript` success
response in the canonical `{"data": {...}}` envelope — today it is the
only personal-agent endpoint returning a flat body, and our
`_handleReply` (`lib/features/api_sync/sync_worker.dart`, ~lines
301-341) depends on that flat shape: it reads top-level `message`
(spoken via TTS), `language`, `conversation_id` (session correlation),
and the session-control signal. The parse sits inside `catch (_) {}`,
so when the server starts enveloping, the client would not crash — it
would silently stop speaking replies, adopting conversation IDs, and
dispatching session control. This proposal makes `_handleReply`
envelope-tolerant **before** the server change deploys.

## Research notes

- The four consumed fields all come from the same decoded map;
  `SessionControlSignal.fromBody(json)` reads from it too — unwrapping
  once covers everything.
- The app already accesses `json['data']` in four repositories
  (`api_chat_repository.dart:109`, `api_plan_repository.dart:57`,
  `api_routines_repository.dart:100`, `api_agenda_repository.dart:51`)
  — this proposal reuses that access pattern, but **tolerant** where
  the repositories are strict: they require the envelope and error on
  its absence; this path falls back to the flat shape. The difference
  is intentional — do not "align" them later.
- The unwrap heuristic cannot misfire against an old (flat) server: the
  flat shape's field set (`message`, `language`, `conversation_id`,
  `session_control`) never contains `data`, and error envelopes
  (`{"data":null,"error":...}`) never reach `_handleReply` because only
  `ApiSuccess` carries a body (`api_client.dart` transcript `post`).
- `testConnection` (`api_client.dart:86`) checks only the 2xx status,
  never the body — the server's test-mode response enveloping needs no
  client change.
- The flat-shape fallback is **permanent**: it keeps every
  client/server version pairing working (new client + old server, old
  prod server, replays), at the cost of two lines.

## Scope

In: `_handleReply` unwrap + unit tests. Out: any other endpoint (the
repositories already handle envelopes), the test-connection path, TTS
behavior, session-control semantics.

## Approach

At the top of `_handleReply`, after `jsonDecode`: if the decoded map
has a `data` key whose value is a `Map<String, dynamic>`, continue with
that inner map; otherwise continue with the decoded map unchanged. All
existing reads (`message`, `language`, `conversation_id`,
`SessionControlSignal.fromBody`) operate on the chosen map. No other
behavior changes.

## Tasks

- T1: envelope-tolerant unwrap in `_handleReply` + unit tests covering:
  flat shape (today's server), enveloped shape (P088 server),
  enveloped shape with session_control, `{"data": null}` and
  `{"data": "str"}` with **no sibling `message`** (silence is
  shape-dependent — fallback reads the outer map, so pin these exact
  bodies), precedence (`{"data":{"message":"inner"},"message":"outer"}`
  speaks "inner"), malformed/non-JSON body (stays silent, as today).
  One PR.

## Acceptance criteria

- AC1: given the flat body, behavior is byte-for-byte today's: TTS
  speaks `message`, `conversation_id` adopted, session control
  dispatched.
- AC2: given `{"data": {...same fields...}}`, the same three behaviors
  fire with identical values.
- AC3: malformed bodies, `data: null`, and non-map `data` values stay
  silent (no throw, no TTS) — same failure mode as today.
- AC4: `flutter analyze` clean and `flutter test` green.

## Deploy order

This build must be installed on the device **before** the
personal-agent P088 server change reaches production. The gate lives as
a journal-agent action item created by P088 T4; this proposal's
implementation merging to main is safe at any time (the unwrap is
backward-compatible).

## Review record

Cross-repo design (including this client-side reader) was reviewed
twice on the P088 side: primary `/proposal-review` and `/codex-review`
second opinion — both read this repo's `sync_worker.dart`,
`api_client.dart`, and the repository unwrap idiom and verified the
analysis against code. This sibling additionally gets its own primary +
architectural pass before implementation per the Tier 3 flow.

## Verification

- `flutter test` (new `_handleReply` cases) + `flutter analyze`.
- Manual (owner, after P088 deploys): speak to the device against the
  enveloped server; confirm TTS reply, conversation correlation, and
  session control.
