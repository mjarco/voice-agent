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
flutter analyze    # Static analysis — zero issues required
flutter test       # All tests must pass
```

Both must pass before any commit or PR.
