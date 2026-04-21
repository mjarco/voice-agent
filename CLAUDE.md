# Voice Agent — Development Instructions for Claude Code

## Project Overview

Voice Agent is a mobile app that records voice, transcribes it via the Groq
cloud STT API (`whisper-large-v3-turbo`), and sends the transcript to the
user's own API endpoint.

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
      data/                 # Service implementations (RecordingServiceImpl, GroqSttService)
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
  This is the only place that imports platform packages (`record`, `dio`, Groq REST client).
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

Use proposals as the default tracking and research artifact for feature work,
behavior changes, and substantial refactors. Keep the process proportional to
risk: design before code, but do not spend full review budget on local or
behavior-preserving work.

### Proposal Usage

- Lightweight proposal: problem, research notes, scope, approach, tasks, acceptance criteria, verification.
- Full proposal: use `/create-proposal` when the change affects architecture, routing, storage, sync contracts, platform/audio behavior, API integration, or multiple feature areas.
- No proposal: truly tiny docs/test/formatting fixes where the PR itself is sufficient history.

### Review Stop Rule

Proposal review is a gate, not a loop.

- If the latest proposal review has no P0, P1, or P2 findings, stop proposal review. Do not run another reviewer just for confidence.
- P3/nits may be fixed opportunistically or left to implementer judgment without re-review.
- If P0/P1 findings are fixed, re-review only the changed proposal sections or run one fresh review if the design changed materially.
- If P2 findings are fixed or explicitly accepted as known trade-offs, re-review only when the fix changes contracts, tasks, acceptance criteria, or architectural decisions.
- Do not run both `/proposal-review` and `/claude-review` for the same purpose; `/claude-review` is the Claude-backed way to run proposal review.

### Risk Tiers

**Tier 0: mechanical, docs, tests, and behavior-preserving refactors**

- Use a lightweight proposal when the work is worth tracking or researching; otherwise use a short PR description or local note.
- Run targeted tests plus `make verify` when feasible.
- Request `/review-pr` only when the diff is non-trivial, production-facing, platform-sensitive, or easy to misread.
- Do not run ADR or implementation reviews.
- Run proposal review only when the proposal records a non-obvious design/research decision.

**Tier 1: small local behavior change**

Examples: UI-only change, single-feature behavior tweak, small settings/storage
extension following an existing pattern.

- Write a lightweight proposal for tracking and research.
- Run one primary proposal review (`/proposal-review` or `/claude-review`).
- Run `/codex-review` only when an independent second opinion is likely to change the design.
- Follow the Review Stop Rule: no P0/P1/P2 means no further proposal review.
- No architectural review unless the change triggers the criteria below.

**Tier 2: normal feature, API integration, storage, navigation, or platform behavior change**

- Create a full proposal in `docs/proposals/` using `/create-proposal`.
- Run one primary proposal review and fix all P0/P1 findings before implementation.
- Fix P2 findings or document them as accepted trade-offs before implementation.
- Run one independent second-opinion review (`/codex-review` or `/claude-review`) when the change touches multiple features/layers, storage schema, API sync contracts, navigation structure, platform audio behavior, permissions, or production integration.
- Follow the Review Stop Rule; re-run reviewers only after substantial proposal rewrites, not after minor wording fixes.
- Run `/proposal-architectural-review` only when the change affects layered architecture, feature boundaries, storage ownership, cross-feature state, routing structure, platform integration patterns, or introduces/amends an ADR.
- If architectural review creates or updates ADRs, wait for explicit user approval before implementing.

**Tier 3: high-risk mobile architecture, data, or platform change**

Examples: sync queue semantics, transcript durability, database migration with
data-loss risk, microphone/session ownership, background behavior, navigation
shell restructure, permission model, or personal-agent API contract changes.

- Use the full Tier 2 flow.
- Require both a primary proposal review and an independent second-opinion review.
- Run `/proposal-architectural-review`.
- Re-review after architectural fixes if they changed proposal contracts, tasks, or acceptance criteria.
- Run `/proposal-implementation-review <proposal-path>` before marking the proposal implemented.

### Proposal and ADR Commit

For Tier 2/3 work, commit approved proposal and ADR changes before implementation:

- The proposal document (`docs/proposals/`)
- All new ADR files (`docs/decisions/`)
- All updates to existing ADR files (`docs/decisions/`)

### Implementation

Every change still goes through a branch and PR; see Git Conventions below.
Proposal tasks may be grouped into one PR when the grouped diff is coherent,
behavior-preserving, and keeps `make verify` green.

1. Create a branch from `main` before editing.
2. Implement the changes.
3. Run `make verify`; all checks must pass unless the change is docs-only.
4. Commit and push, then create a PR. Reference the proposal or issue when one exists.
5. Run `/review-pr` for Tier 2/3 work, non-trivial Tier 1 work, and any production hotfix after the immediate fix is safe.
6. Fix all blocker findings before merge.
7. Merge the PR to `main`.

Implement approved proposals end-to-end autonomously. Avoid commands that require
human interaction: use non-interactive flags, temp files for multiline content,
and `gh pr merge --auto` or direct merge when appropriate.

### Hotfix Lane

For production or device-blocking incidents, prioritize the smallest safe fix:

1. Diagnose and patch the immediate failure.
2. Run the narrowest reliable verification plus broader checks when time allows.
3. Ship or merge if needed.
4. After stable, add proposal/ADR/review follow-up only if the fix introduced new intended behavior or an architectural decision.

### Close Out

After Tier 2/3 proposal work is merged, run `/proposal-implementation-review`
only when the proposal had multiple PRs, changed contracts/invariants, or carried
high data/architecture/platform risk. Update proposal status to `Implemented`
after required review gates pass.

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
make verify        # Runs analyze + test
```

`make verify` must pass before any commit or PR. Use `make analyze` or
`make test` only when you need a narrower diagnostic command.

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
- **Data**: Service implementations with mocked platform packages (AudioRecorder, Groq HTTP client).
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

# After make verify passes:
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

- [ ] `make verify` passes
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
- The shell uses `StatefulShellRoute.indexedStack` with 5 tabs (Agenda, Plan, Record, Routines, Chat).
- Child routes (e.g., `/record/history`) stay within their branch.
- Navigation arguments pass via GoRouter `extra` parameter.
- P020 established the 5-branch route structure. Feature proposals (P021–P024)
  **replace placeholder screens** in existing routes — they do not add new
  top-level routes.
- Infrequently accessed screens (e.g., Settings) are top-level GoRoutes outside
  the shell. Navigate to them with `context.push()` (not `context.go()`) to
  preserve shell state.

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
| Services (impl) | abstract name + Impl | `RecordingServiceImpl`, `GroqSttService` |
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

### Route Ownership (008, 020 → 001, 006, 007, 021–024)

P020 restructured the shell to 5 branches. Feature proposals replace
placeholder screens within this structure — they do not add routes.

| Route | Owner | Content owner |
|-------|-------|---------------|
| `/agenda` | 020 (shell branch 0) | 021 (AgendaPlaceholderScreen → real screen) |
| `/plan` | 020 (shell branch 1) | 023 (PlanPlaceholderScreen → real screen) |
| `/record` | 020 (shell branch 2) | 001 (RecordingScreen) |
| `/record/history` | 020 (child of /record) | 007 (HistoryScreen) |
| `/record/history/:id` | 020 (child of /record/history) | 007 (TranscriptDetailScreen) |
| `/routines` | 020 (shell branch 3) | 022 (RoutinesPlaceholderScreen → real screen) |
| `/chat` | 020 (shell branch 4) | 024 (ChatPlaceholderScreen → real screen) |
| `/settings` | 020 (outside shell) | 006 (SettingsScreen) |
| `/settings/advanced` | 020 (child of /settings) | 013 (AdvancedSettingsScreen) |

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
make setup                   # Full setup: flutter pub get + download Silero VAD model
make deps                    # Flutter pub get only
make vad-model               # Download Silero VAD v5 ONNX model (~2 MB)
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
