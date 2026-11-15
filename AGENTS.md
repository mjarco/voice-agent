# AGENTS.md

## Project Context

Voice Agent is a Flutter mobile app (iOS + Android) that records voice,
transcribes via the Groq cloud STT API (`whisper-large-v3-turbo`), and sends
transcripts to the user's API.

Architecture: layered (features/ core/ app/). Stack: Flutter 3.22+, Dart 3.4+,
Riverpod, GoRouter, sqflite, Silero VAD (local), Groq Whisper (cloud STT).

See CLAUDE.md for architecture rules, coding conventions, and cross-proposal contracts.

## Verification Commands

```bash
make verify-changed  # analyze + the tests of the touched modules — before each commit
make verify          # analyze + the full suite — before the PR goes ready and every push to it
```

Details: Verification Gates in CLAUDE.md.
