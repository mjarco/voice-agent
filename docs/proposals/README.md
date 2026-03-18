# Voice Agent — Proposals

## MVP Implementation Order

```
000 Project Bootstrap
 ├── 008 App Navigation & UI Shell
 ├── 004 Local Storage & Offline Queue
 │    ├── 005 API Sync Client
 │    │    └── 006 Settings Screen
 │    └── 007 Transcript History
 ├── 001 Audio Capture
 │    └── 002 Speech-to-Text Engine
 │         └── 003 Transcript Review & Edit
```

## Proposals

| # | Title | Depends On | Risk | Tasks | Status |
|---|-------|-----------|------|-------|--------|
| 000 | [Project Bootstrap](000-project-bootstrap.md) | — | Low | 2 | Draft |
| 001 | [Audio Capture](001-audio-capture.md) | 000 | Medium | 4 | Draft |
| 002 | [Speech-to-Text Engine](002-speech-to-text-engine.md) | 000, 001 | High | 4 | Draft |
| 003 | [Transcript Review & Edit](003-transcript-review.md) | 002 | Low | 3 | Draft |
| 004 | [Local Storage & Offline Queue](004-local-storage.md) | 000 | Medium | 4 | Draft |
| 005 | [API Sync Client](005-api-sync.md) | 004 | Medium | 4 | Draft |
| 006 | [Settings Screen](006-settings-screen.md) | 005 | Low | 4 | Draft |
| 007 | [Transcript History](007-history-screen.md) | 004 | Low | 4 | Draft |
| 008 | [App Navigation & UI Shell](008-app-navigation.md) | 000 | Low | 3 | Draft |

## Implementation Phases

**Phase 1 — Foundation:** 000, 008, 004
**Phase 2 — Core flow:** 001, 002, 003
**Phase 3 — Sync:** 005, 006
**Phase 4 — Polish:** 007

## Ownership Boundaries

Each proposal owns specific dependencies and code areas. Key boundaries:

| Concern | Owner | Package |
|---------|-------|---------|
| App shell, routing | 000 (structure), 008 (shell) | `go_router` |
| State management | 000 | `flutter_riverpod` |
| Audio recording | 001 | `record`, `permission_handler`, `path_provider` |
| Speech-to-text | 002 | `whisper_flutter_new` |
| Database, models | 004 | `sqflite`, `uuid` |
| HTTP, connectivity | 005 | `dio`, `connectivity_plus` |
| Settings persistence | 006 | `shared_preferences`, `flutter_secure_storage` |
| API URL banner (stub) | 008 (stub), 006 (real impl) | — |
