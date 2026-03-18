# Proposal 000 — Project Bootstrap

## Status: Draft

## Prerequisites
None — this is the root of the dependency tree.

## Scope
- Tasks: ~2
- Layers: app, core, features (directory structure only)
- Risk: Low — standard Flutter scaffolding

---

## Problem Statement

There is no project yet. Every downstream proposal (001–008) needs a working Flutter
project with a defined directory structure, resolved dependencies, linting configuration,
and a buildable app shell. Without this foundation, each proposal would independently
make structural decisions, leading to inconsistency.

---

## Are We Solving the Right Problem?

**Root cause:** The project does not exist. There is no `pubspec.yaml`, no directory
structure, no lint rules, no buildable artifact.

**Alternatives dismissed:**
- *Let each feature proposal set up its own structure:* Would cause conflicting
  architectural decisions (different state management patterns, inconsistent directory
  layout). The bootstrap exists precisely to lock in shared decisions once.
- *Use a Flutter starter template (e.g., very_good_cli):* Introduces opinions and
  boilerplate we may not need (bloc instead of Riverpod, built-in localization, CI
  templates). Simpler to scaffold manually and add only what we need.

**Smallest change?** Yes — this proposal does only scaffolding. Feature-specific
packages (audio, STT) are deferred to their respective proposals (001, 002).

---

## Goals

- Establish the canonical directory structure that all proposals build on
- Lock in shared tooling decisions (state management, navigation, linting)
- Produce a buildable app shell on both iOS and Android

## Non-goals

- No feature code — recording, STT, storage, sync are all in later proposals
- No CI/CD setup — add when the first PR workflow is needed
- No flavor configuration (dev/prod) — single build target for MVP
- No design system or custom theme — Material 3 defaults are sufficient for now
- No IDE-specific configuration (`.vscode/`, `.idea/`)

---

## User-Visible Changes

After this proposal, launching the app shows a placeholder home screen with the app
name. No functionality — just proof that the shell builds and runs on both platforms.

---

## Solution Design

### Directory Structure

```
lib/
  app/                  # App-level config, theme, routes
    app.dart            # MaterialApp + ProviderScope + GoRouter
    router.dart         # Route definitions
  features/
    recording/          # (empty — populated by 001)
    transcript/         # (empty — populated by 003)
    api_sync/           # (empty — populated by 005)
    history/            # (empty — populated by 007)
  core/
    storage/            # (empty — populated by 004)
    network/            # (empty — populated by 005)
    models/             # (empty — populated by 004)
  main.dart             # Entry point
test/
  app/
    app_test.dart       # Smoke test — app renders without crashing
```

Feature directories are created as empty placeholders with `.gitkeep` files.
This makes the architecture visible from day one without introducing dead code.

### Key Decisions

**State management: Riverpod (manual providers, not codegen).**
Using `flutter_riverpod` with manual `Provider`/`StateNotifierProvider` declarations.
Codegen (`riverpod_generator`) adds build_runner complexity for little benefit at this
scale. Can be adopted later if provider count grows significantly.

**Navigation: GoRouter (package selection only).**
Bootstrap adds `go_router` as a dependency and creates a single `/` placeholder route.
The shell navigation structure (`ShellRoute`, bottom navigation, tab routing) is owned
entirely by Proposal 008. Bootstrap does NOT set up any shell abstraction — just a
flat route list with one entry.

**Linting: `flutter_lints` (official Flutter team rules).**
The default `flutter_lints` package provides a sensible baseline. No need for
`very_good_analysis` — its stricter rules add friction without proportional benefit
for a small project.

**No database dependency in bootstrap.**
Database package choice (`sqflite` vs `drift`) is deferred to Proposal 004 (Local
Storage), which owns that decision. Bootstrap only provides the `core/storage/`
directory placeholder.

### Dependencies (bootstrap only)

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.5 | State management |
| `go_router` | ^14.0 | Navigation |
| `flutter_lints` | ^4.0 | Linting rules (dev) |

All other dependencies (dio, sqflite/drift, connectivity_plus, record, whisper) are
added by their respective proposals when needed.

### Platform Configuration

| Setting | Value |
|---------|-------|
| Org / bundle ID | `com.voiceagent.app` |
| Android minSdk | 24 (Android 7.0) |
| Android targetSdk | 34 |
| iOS deployment target | 16.0 |
| Flutter SDK | >=3.22.0 |
| Dart SDK | >=3.4.0 |

---

## Affected Mutation Points

Not applicable — greenfield project, no existing code is modified.

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Scaffold project: `flutter create`, directory structure, dependencies, platform config, linting, `main.dart` with ProviderScope + GoRouter + placeholder screen. Include smoke test. | app, core, features |
| T2 | Verify build on iOS and Android (physical device or simulator). Fix any platform-specific build issues. | infra |

### T1 details

- Run `flutter create --org com.voiceagent .` from the repo root (in-place scaffold,
  not a nested subdirectory — the repo root IS the Flutter project root)
- Restructure `lib/` into `app/`, `features/`, `core/` with `.gitkeep` in empty dirs
- Remove any template files generated by `flutter create` that are not needed
  (e.g., default `lib/main.dart` content, default widget test)
- Add `flutter_riverpod` and `go_router` to `pubspec.yaml`
- Replace default `analysis_options.yaml` with `flutter_lints` include
- Set `minSdkVersion 24` in `android/app/build.gradle`
- Set iOS deployment target `16.0` in `ios/Podfile` and Xcode project
- Create `lib/main.dart` → `lib/app/app.dart` with `ProviderScope` wrapping `MaterialApp.router`
- Create `lib/app/router.dart` with a single `/` route pointing to a `PlaceholderHomeScreen`
- Create `test/app/app_test.dart` — pumps `App` widget, verifies it renders without error
- Add `.gitignore` (Flutter default + `.env`, `*.jks`, `*.keystore`)
- The repo already exists — do NOT run `git init` (the project directory is the repo root)

### T2 details

- Run `flutter build apk --debug` and `flutter build ios --debug --no-codesign`
- Run `flutter test`
- Run `flutter analyze`
- Fix any issues surfaced by build/test/analyze
- This is a verification task, not a coding task — no PR unless fixes are needed

---

## Test Impact

### Existing tests affected
None — greenfield project.

### New tests
- `test/app/app_test.dart` — smoke test that `App` widget renders without crash
- Run with: `flutter test`

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes (at least 1 test: app smoke test).
3. `flutter build apk --debug` succeeds.
4. `flutter build ios --debug --no-codesign` succeeds.
5. Directory structure matches the specification in Solution Design.
6. `pubspec.yaml` `dependencies:` section contains exactly `flutter`, `flutter_riverpod`,
   and `go_router`. `dev_dependencies:` section contains exactly `flutter_test` (SDK)
   and `flutter_lints`. No template residue (e.g., `cupertino_icons` removed unless
   explicitly kept).
7. `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`.
8. Android `minSdkVersion` is 24, iOS deployment target is 16.0.
9. App launches on a device/simulator and shows the placeholder screen.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Flutter SDK version mismatch across machines | Pin SDK version in `pubspec.yaml` environment block |
| GoRouter + Riverpod integration issues | Both are widely used together, well-documented patterns exist |
| `flutter create .` generates template files that conflict with desired structure | T1 explicitly removes template residue and replaces with project structure |
| Proposal 008 scope overlap on navigation | 000 owns only package selection + single `/` placeholder route; 008 owns ShellRoute and bottom nav — boundary is explicit in both proposals |

---

## Known Compromises and Follow-Up Direction

### No flavor configuration (V1 pragmatism)
Single build target for now. When we need separate API endpoints for dev/prod,
add flavor support. Not needed until Proposal 005 (API Sync) or later.

### Empty feature directories
`.gitkeep` files in empty directories is a minor hack. They disappear naturally
as each proposal adds real files. Acceptable for making architecture visible early.
