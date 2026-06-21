# Voice Agent — Proposals

Index of design proposals. Status is recorded in the `## Status:` line at the top of each proposal file; this index is a roll-up.

## Status legend

- **Implemented** — design shipped to `main` and in use.
- **Superseded** — replaced by a later proposal; do not implement as written.
- **Reverted** — was implemented, then rolled back; do not resurrect without a new proposal.
- **Draft (seed)** — recorded but not designed in full; needs work before implementation.
- **Post-mortem** — historical record of an incident, not a feature proposal.
- **PoC** — throwaway proof-of-concept; may or may not graduate into a real proposal.

## Index

| # | Title | Status |
|---|-------|--------|
| 000 | [Project Bootstrap](000-project-bootstrap.md) | Implemented |
| 001 | [Audio Capture](001-audio-capture.md) | Implemented |
| 002 | [Speech-to-Text Engine](002-speech-to-text-engine.md) | Implemented |
| 003 | [Transcript Review & Edit](003-transcript-review.md) | Implemented |
| 004 | [Local Storage & Offline Queue](004-local-storage.md) | Implemented |
| 005 | [API Sync Client](005-api-sync.md) | Implemented |
| 006 | [Settings Screen](006-settings-screen.md) | Implemented |
| 007 | [Transcript History](007-history-screen.md) | Implemented |
| 008 | [App Navigation & UI Shell](008-app-navigation.md) | Implemented |
| 009 | [Code Review Fixes](009-code-review-fixes.md) | Implemented |
| 010 | [iOS Debug Session](010-ios-debug-session.md) | Post-mortem (PR #69) |
| 011 | [Groq Cloud STT](011-groq-stt.md) | Implemented |
| 012 | [Hands-Free Local VAD](012-hands-free-local-vad.md) | Implemented |
| 013 | [VAD Advanced Settings](013-vad-advanced-settings.md) | Implemented |
| 014 | [Recording Mode Overhaul](014-recording-mode-overhaul.md) | Implemented |
| 015 | [TTS Response Playback](015-tts-response-playback.md) | Implemented |
| 016 | [Audio Feedback During Processing](016-audio-feedback.md) | Implemented |
| 017 | [Personal Agent Integration](017-personal-agent-integration.md) | Implemented |
| 018 | [Sync Reliability Fixes](018-sync-reliability-fixes.md) | Implemented |
| 019 | [Background Activation & Wake Word](019-background-activation-wake-word.md) | Reverted by P026 — wake word dropped |
| 020 | [Navigation Restructure (5-tab)](020-navigation-restructure.md) | Implemented |
| 021 | [Agenda Screen](021-agenda-screen.md) | Implemented |
| 022 | [Routines Screen](022-routines-screen.md) | Implemented |
| 023 | [Plan Screen](023-plan-screen.md) | Implemented |
| 024 | [Chat Screen](024-chat-screen.md) | Implemented |
| 025 | [Shared API Client Layer](025-shared-api-layer.md) | Implemented |
| 026 | [Remove Wake Word & Whisper Traces](026-remove-wake-word-and-whisper-traces.md) | Implemented |
| 027 | [Background Sync (Hands-Free)](027-background-sync.md) | Implemented |
| 028 | [Background TTS (Hands-Free)](028-background-tts.md) | Implemented |
| 029 | [Honor Session-Control Signals](029-honor-session-control-signals.md) | Implemented |
| 030 | [TTS Mixed-Language SSML](030-tts-mixed-language-ssml.md) | Implemented |
| 031 | [VAD Hangover Tuning](031-vad-hangover-tuning.md) | Draft (seed) |
| 032 | [New Conversation Button](032-new-conversation-button.md) | Implemented |
| 033 | [API Cost Dashboard](033-api-cost-dashboard.md) | Implemented (client; awaits backend aggregation endpoint) |
| 034 | [AirPods / Media Button Pause & Resume](034-airpods-media-button-control.md) | Superseded by P038 |
| 035 | [Dual Installation via Flavors](035-dual-installation-flavors.md) | Implemented |
| 036 | [Replay Last TTS Reply](036-replay-last-tts.md) | Implemented |
| 037 | [Hardware-Button Control of Hands-Free Listening](037-airpods-listening-control.md) | Superseded by P038 (proposal PR #272 closed) |
| 038 | [Always-On Capture with Volume-Button Engagement](038-always-on-capture-volume-button-engagement.md) | Implemented |
| 039 | [OTel Dev Telemetry](039-otel-dev-telemetry.md) | Implemented |
| 040 | [Agenda Notifications & Background Refresh](040-agenda-notifications-and-background-refresh.md) | Implemented (manual device verification pending) |
| 041 | [Suppress Spurious Volume Events During Audio-Session Transitions](041-volume-button-spurious-event-on-session-start.md) | Reverted — fixed a non-bug (see P042 §Relationship to P041) |
| 042 | [Recover Hands-Free Capture Across Audio Route Changes](042-recover-hands-free-capture-across-route-changes.md) | Implemented (device-verified 2026-05-22; T3 wired outstanding) |
| 045 | [Pins (Saved References) Screen](045-pins-screen.md) | Implemented |
| — | [PoC: "Come back" notification](POC-come-back-notification.md) | PoC implemented (PR #288) |
| — | [Backlog](P000-backlog.md) | — |

## Architecture decision records

Architecture decisions live in [`../decisions/`](../decisions/). Recent ADRs of note:

- **ADR-AUDIO-009** — superseded by ADR-AUDIO-011 (P038)
- **ADR-AUDIO-010** — iOS media-button routing constraints (drove the P037 → P038 pivot)
- **ADR-AUDIO-011** — always-on capture with explicit engagement gate (P038)

## Notes

- The historical Phase-1 dependency tree (proposals 000–008) drove MVP delivery; everything from 009 onward landed incrementally and is recorded here as a flat list.
- When in doubt about a proposal's current status, the `## Status:` line at the top of the proposal file is authoritative — this index is a roll-up that may lag.
