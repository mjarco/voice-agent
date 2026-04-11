# Voice Agent — Development Instructions for Claude Code

## Project Overview

Voice Agent is an offline-first mobile app that records voice, transcribes it
on-device using Whisper, and sends the transcript to the user's own API endpoint.

**Platforms**: iOS 16+, Android SDK 24+ (Android 7.0).
**Architecture**: Layered (features / core / app).
**Language**: Dart 3.4+ / Flutter 3.22+.
**State management**: Riverpod (manual providers, no codegen).
**Navigation**: GoRouter with StatefulShellRoute.

---

## Architecture Rules — MANDATORY

These rules are non-negotiable. Every change must respect them.

### Dependency Rule

```
features/  →  core/  ←  app/
features/ do NOT import from other features/
```

- **core/** contains shared models, storage abstractions, network abstractions,
  and providers. It imports nothing from `features/` or `app/`.
- **features/** contains self-contained feature modules (recording, transcript,
  api_sync, history, settings). Each feature imports only from `core/` and from
  within its own directory. **Features never import from other features.**
- **app/** contains app-level configuration (router, theme, root widget). It
  imports from `core/` and `features/`.

**Violation of the dependency rule is a blocker. Never merge code that breaks it.**

### How to Verify

```bash
# Features must not import from other features
grep -r "import.*features/" lib/features/recording/ | grep -v "features/recording" && echo "VIOLATION" || echo "OK"
grep -r "import.*features/" lib/features/transcript/ | grep -v "features/transcript" && echo "VIOLATION" || echo "OK"
grep -r "import.*features/" lib/features/api_sync/ | grep -v "features/api_sync" && echo "VIOLATION" || echo "OK"
grep -r "import.*features/" lib/features/history/ | grep -v "features/history" && echo "VIOLATION" || echo "OK"
grep -r "import.*features/" lib/features/settings/ | grep -v "features/settings" && echo "VIOLATION" || echo "OK"

# Core must not import features or app
grep -r "import.*features/" lib/core/ && echo "VIOLATION" || echo "OK"
grep -r "import.*app/" lib/core/ && echo "VIOLATION" || echo "OK"
```

### Directory Structure

```
lib/
  app/                      # App-level config, theme, routes
    app.dart                # MaterialApp + ProviderScope + GoRouter
    router.dart             # StatefulShellRoute + all route definitions
    app_shell_scaffold.dart # Bottom navigation shell
  features/
    recording/              # Audio capture + STT
      data/                 # Service implementations (RecordingServiceImpl, WhisperSttService)
      domain/               # Interfaces + models (RecordingService, SttService, RecordingState)
      presentation/         # UI + controllers (RecordingScreen, RecordingController)
    transcript/             # Review, edit, approve/cancel
    api_sync/               # Sync worker + providers
    history/                # Transcript history list
    settings/               # Settings screen + persistence
  core/
    models/                 # Shared data models (Transcript, SyncQueueItem, SyncStatus)
    storage/                # StorageService interface + SQLite implementation
    network/                # ApiClient, ConnectivityService
    providers/              # Shared providers (apiUrlConfiguredProvider, etc.)
  main.dart                 # Entry point
```

### Layer Guidelines

- **Domain types** (in `features/*/domain/`) are abstract interfaces and sealed
  state classes. No platform imports, no persistence logic.
- **Data implementations** (in `features/*/data/`) implement domain interfaces.
  This is the only place that imports platform packages (`record`, `whisper_flutter_new`).
- **Presentation** (in `features/*/presentation/`) contains screens, controllers
  (StateNotifier), and Riverpod providers. Controllers depend on domain interfaces,
  never on data implementations directly.
- **Core models** are plain Dart classes with `fromMap`/`toMap` for SQLite
  serialization. No codegen (no freezed, no json_serializable).
- Never put business logic in data implementations. If an adapter is doing more
  than format conversion + platform call, the logic belongs in the controller or
  domain layer.

### Architecture Decision Records (ADRs)

Architectural decisions are tracked in `docs/decisions/` as ADR files. The `/proposal-architectural-review` skill checks proposals against existing ADRs and drafts new ADRs for undocumented decisions.

- ADR naming: `ADR-{NNN}-{short-description}.md`
- ADRs are committed alongside the proposal they originate from (Phase B)
- When modifying code, check relevant ADRs for constraints

---

## Development Workflow

### Feature Lifecycle (mandatory for new features and behavior changes)

Every feature or behavior change follows this pipeline **in order**:

#### Phase A — Proposal (design before code)

```
A1. /create-proposal           — write proposal in docs/proposals/{NNN}-{name}.md
A2. /proposal-review           — review proposal
A3. Fix review issues           — address all P0/P1 issues found by the reviewer
A4. Repeat A2–A3               — re-review until verdict: Ready
A5. /codex-review              — ask Codex to review the proposal (round 1)
A6. Fix Codex issues           — address issues raised by Codex
A7. /codex-review (re-read)    — ask Codex to re-read the proposal and review again;
                                 explicitly instruct Codex to read the proposal file
                                 again before reviewing (it retains session context
                                 but must be told to re-read for the latest version)
A8. Fix Codex issues           — address remaining issues from round 2
A9. /proposal-architectural-review — ADR compliance + new ADR drafts for undocumented
                                     decisions introduced by the proposal
A10. Fix architectural findings — fix all ADR violations before proceeding
A11. User approval             — wait for explicit user approval of proposal + ADRs
A12. /proposal-review          — post-architecture review to catch inconsistencies
                                 introduced by architectural fixes
```

#### Phase B — Proposal and ADRs land on main

```
B1. Create a branch for the proposal document (e.g. docs/p{NNN}-proposal)
B2. Commit the proposal file + all new/updated ADR files (docs/decisions/)
B3. Push and create a PR
B4. Merge the PR
```

#### Phase C — Create tracked issues

```
C1. /create-github-issues     — create one GitHub issue per task from the proposal
```

#### Phase D — Implement tasks (repeat for each task or batch of tasks)

```
D1. Create a feature branch from main (e.g. feat/p{NNN}-t{N}-short-name)
D2. Implement the changes
D3. Run `flutter test && flutter analyze` — all checks must pass
D4. Commit and push, create a PR referencing the GitHub issue
D5. /review-pr <N> — self-review using code review skills
D6. Implement fixes from the review
D7. Repeat D5–D6 until quality is sufficient (max 3 review iterations)
D8. Approve and merge the PR to main
```

**Rules:**
- Never skip phases. Never start implementation before proposal is approved.
- Never create GitHub issues for an unapproved proposal.
- **Autonomous execution.** The entire pipeline from Phase B through Phase D
  runs without waiting for user reaction at intermediate steps. Do not stop
  to ask for confirmation between tasks, between iterations, or before
  merging. The user delegates execution and expects finished results.
- **Avoid generating commands that require human interaction.** Use non-interactive
  flags, write multiline content to temp files, and prefer `gh pr merge --auto`
  or direct merge over workflows that block on manual approval.
- Phase A (proposal) requires user approval at step A11 — this is the only
  mandatory human checkpoint. Everything after A11 is autonomous.

#### Phase E — Close out

After all tasks are merged, update proposal status to `Implemented`.

**Not needed for:** bug fixes that don't change intended behavior, refactoring
with no behavioral impact, test-only changes, documentation fixes. For these,
skip directly to Phase D.

### Before Writing Code

1. **Read the relevant proposal** in `docs/proposals/` to understand the design intent.
2. **Read existing code** in the area you're modifying. Understand patterns before changing them.

### Writing Code

1. Start with domain types/interfaces if they don't exist yet.
2. Write the data implementation that implements the interface.
3. Write the controller (StateNotifier) that orchestrates the domain logic.
4. Write the screen (ConsumerWidget/ConsumerStatefulWidget) that renders state.
5. Add Riverpod providers and register routes in `router.dart`.

### After Writing Code — Mandatory Checks

```bash
flutter analyze    # Static analysis — zero issues required
flutter test       # All tests must pass
```

Both must pass before any commit or PR.

---

## Testing Strategy

### Test Placement

```
test/
  app/                          # App-level tests (router, shell, smoke)
  core/
    models/                     # Model serialization round-trip tests
    storage/                    # Integration tests with in-memory SQLite
  features/
    recording/
      data/                     # Unit tests for service implementations (mocked platform)
      presentation/             # Controller state-transition tests, widget tests
    transcript/                 # Widget tests for review screen
    api_sync/                   # Sync worker tests (mocked storage + HTTP)
    history/                    # List rendering, pagination, action tests
    settings/                   # Service persistence tests, widget tests
```

### Test Conventions

- Use `flutter_test` (standard Flutter testing).
- Use `mocktail` or Riverpod overrides for mocking dependencies.
- Use `sqflite_common_ffi` with in-memory database for storage integration tests.
- Widget tests use `pumpWidget` with `ProviderScope(overrides: [...])`.
- Group related tests with `group()`.
- Name test files `*_test.dart` in the matching directory structure.

### What to Test

- **Domain**: All state transitions, sealed class exhaustiveness, interface contracts.
- **Data**: Service implementations with mocked platform packages (AudioRecorder, Whisper FFI).
- **Controllers**: State machine transitions with mocked services.
- **Widgets**: Button states, navigation triggers, conditional rendering, error states.
- **Storage**: CRUD operations, sync queue state machine, pagination, cascade deletes.
- **Network**: Response classification (2xx/4xx/5xx), timeout handling, retry logic.

### What NOT to Test

- Flutter framework internals (MaterialApp renders, Navigator works).
- Trivial getters on model classes.
- Platform behavior that can only be verified on a physical device (mark those
  acceptance criteria as "manual verification" in proposals).

---

## Git Conventions

### Avoid Heredocs in Shell Commands

**Never use heredocs (`<<EOF`, `<<'EOF'`) in `gh` or `git` commands.**
They cause quoting issues, break in some shells, and are hard to debug.
Instead, use the `-F` flag with a temp file, or pass short strings directly
with `--body "..."` / `-m "..."`.

```bash
# BAD — heredoc
gh pr create --body "$(cat <<'EOF'
...
EOF
)"

# GOOD — temp file
echo "PR body here" > /tmp/pr-body.md
gh pr create --body-file /tmp/pr-body.md

# GOOD — short inline string
gh pr create --body "Summary of changes"
```

### The Golden Rule — Never Push Directly to `main`

**Every change goes through a branch and a PR. No exceptions. This includes
documentation fixes, config changes, one-line edits, and wiring changes.**

```bash
# Before starting any work — always:
git checkout -b feat/my-feature   # or fix/, docs/, chore/, refactor/

# After flutter test && flutter analyze pass:
git push -u origin feat/my-feature
gh pr create --title "..." --body "..."
```

`main` is the integration branch. Direct pushes to `main` are **forbidden**.
The only commits that land on `main` are merged PRs.

**This rule applies to Claude Code unconditionally.**
- Never use `git commit` on `main`.
- Never use `git push` on `main`.
- If already on `main` with uncommitted changes: create a branch first, then commit.
- If already on `main` with committed-but-unpushed changes: create a branch,
  cherry-pick or reset main, push the branch, open a PR.
- Always create a branch at the start of any task, before writing the first line of code.

### Branch Naming

```
feat/<short-description>     # New feature
fix/<short-description>      # Bug fix
refactor/<short-description> # Refactoring
docs/<short-description>     # Documentation
chore/<short-description>    # Build, CI, tooling
```

### Commit Messages

Use conventional commits:

```
feat(recording): add RecordingService with 16kHz WAV capture

Implements the RecordingService interface and RecordingServiceImpl
using the record package. Configures AudioEncoder.wav at 16kHz mono.
```

Format: `type(scope): description`

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`
Scope: feature or layer name (e.g., `recording`, `core/storage`, `app`)

### PR Checklist

Before requesting review, verify:

- [ ] `flutter analyze` passes with zero issues
- [ ] `flutter test` passes with all tests green
- [ ] Architecture dependency rule is respected (no cross-feature imports)
- [ ] New code has tests
- [ ] No hardcoded secrets, tokens, or credentials
- [ ] No TODO without a linked issue
- [ ] No debugging artifacts (`print()`, `debugPrint()`)

---

## Coding Conventions

### State Management

All state is managed via Riverpod:

```dart
// Controllers use StateNotifier:
class RecordingController extends StateNotifier<RecordingState> {
  RecordingController(this._recordingService) : super(const RecordingState.idle());
  final RecordingService _recordingService;
}

// Providers are declared per-feature:
final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordingState>((ref) {
  return RecordingController(ref.watch(recordingServiceProvider));
});
```

- Use `StateNotifierProvider` for mutable state with business logic.
- Use `Provider` for injecting services and configuration.
- Use `FutureProvider` for async one-shot data loading.
- Use `FutureProvider.family` when the query needs a parameter.
- **Never use global singletons.** All dependencies flow through Riverpod.

### Navigation

All navigation uses GoRouter:

- Routes are defined in `lib/app/router.dart`.
- The shell uses `StatefulShellRoute.indexedStack` with 3 tabs.
- Child routes (e.g., `/record/review`) stay within their branch.
- Navigation arguments pass via GoRouter `extra` parameter.
- Feature proposals **replace placeholder screens** in existing routes — they
  do not add new top-level routes.

### Error Handling

```dart
// Always catch and handle — never silently swallow:
try {
  await service.doSomething();
} catch (e) {
  state = RecordingState.error('Failed to start recording: $e');
}

// Use typed exceptions for domain-level errors:
class SttException implements Exception {
  final String message;
  SttException(this.message);
}

// Show errors to the user via state, not raw exceptions:
// Controller catches → updates state → UI renders error state
```

### Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Services (abstract) | domain concept | `RecordingService`, `SttService`, `StorageService` |
| Services (impl) | abstract name + Impl | `RecordingServiceImpl`, `WhisperSttService` |
| Controllers | feature + Controller | `RecordingController`, `HistoryNotifier` |
| Providers | camelCase + Provider | `recordingServiceProvider`, `appSettingsProvider` |
| Screens | feature + Screen | `RecordingScreen`, `TranscriptReviewScreen` |
| States (sealed) | feature + State | `RecordingState.idle()`, `RecordingState.recording()` |
| Models | noun | `Transcript`, `SyncQueueItem`, `AppSettings` |
| Enums | noun | `SyncStatus`, `DisplaySyncStatus`, `ConnectivityStatus` |

### File Organization

- One major class per file (screen, controller, service, model).
- File name matches class name in snake_case: `RecordingScreen` → `recording_screen.dart`.
- Don't create `utils.dart` or `helpers.dart` — put functions near their callers.
- Don't create `constants.dart` — put constants with the types they relate to.
- Feature directory structure: `data/`, `domain/`, `presentation/`.

---

## Cross-Proposal Contracts

These are the key integration points between proposals. When modifying code near
these boundaries, verify both sides match.

### Audio Format Contract (001 → 002)

Proposal 001 produces WAV files. Proposal 002 consumes them.

| Setting | Value | Owner |
|---------|-------|-------|
| Sample rate | 16 kHz | 001 |
| Channels | Mono | 001 |
| Encoding | PCM 16-bit | 001 |
| Format | WAV (`AudioEncoder.wav`) | 001 |
| Validation | Rejects non-16kHz input | 002 |

### TranscriptResult Contract (002 → 003)

```
TranscriptResult {
  text: String
  segments: List<TranscriptSegment>
  detectedLanguage: String       // ISO 639-1
  audioDurationMs: int
}
```

Passed via GoRouter `extra` to `/record/review`.

### StorageService Contract (004 → 003, 005, 007, 018)

```
StorageService {
  saveTranscript(Transcript)
  getTranscript(String id) → Transcript?
  getTranscripts({limit, offset}) → List<Transcript>
  deleteTranscript(String id)
  enqueue(String transcriptId)
  getPendingItems() → List<SyncQueueItem>
  markSending(String id)
  markSent(String id)            // DELETES the sync_queue row
  markFailed(String id, String error, {int? overrideAttempts})  // P018-T2
  markPendingForRetry(String id) // clears error_message (P018-T2)
  getFailedItems({int? maxAttempts}) → List<SyncQueueItem>      // P018-T2
  getDeviceId() → String
  recoverStaleSending() → int   // P018-T1: resets sending→pending
}
```

### Sync Queue State Machine (004, 005)

```
[pending] → [sending] → (row deleted via markSent)
                ↓
            [failed] → [pending] (via markPendingForRetry after backoff)
```

- `sent` is NOT a persisted state — sent rows are deleted.
- History (007) derives "sent" from absence of a sync_queue row.
- `SyncStatus` enum: `{ pending, sending, failed }` (no `sent`).
- `DisplaySyncStatus` enum (view-level, 007 only): `{ sent, pending, failed }`.

### Route Ownership (008 → 001, 003, 006, 007)

Proposal 008 owns the shell and all top-level routes. Feature proposals
**replace placeholders**, they do not add routes.

| Route | Shell owner | Content owner |
|-------|-------------|---------------|
| `/record` | 008 | 001 (RecordingScreen) |
| `/record/review` | 008 | 003 (TranscriptReviewScreen) |
| `/history` | 008 | 007 (HistoryScreen) |
| `/settings` | 008 | 006 (SettingsScreen) |

### Stub Provider Pattern (005, 008 → 006)

Two proposals define stub providers that 006 replaces:

| Stub | Defined by | Returns | Replaced by 006 with |
|------|-----------|---------|---------------------|
| `apiConfigProvider` | 005 | `ApiConfig(url: null)` | Real provider reading from `appSettingsProvider` |
| `apiUrlConfiguredProvider` | 008 | `false` | Real provider checking if URL is set |

---

## Quick Reference

```bash
# Makefile targets (preferred)
make setup                   # Full setup: flutter pub get + download Whisper model
make deps                    # Flutter pub get only
make model                   # Download Whisper base model (~140 MB)
make verify                  # Run analyze + test
make analyze                 # Static analysis only
make test                    # Run tests only
make clean                   # Remove build artifacts and downloaded models

# Direct Flutter commands
flutter analyze              # Static analysis — zero issues required
flutter test                 # Run all tests
flutter test --coverage      # With coverage report
flutter build apk --debug    # Android debug build
flutter build ios --debug --no-codesign  # iOS debug build
```
