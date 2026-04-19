# Proposal 008 — App Navigation & UI Shell

## Status: Implemented

## Prerequisites
- Proposal 000 (Project Bootstrap) — provides `lib/app/router.dart`, GoRouter dependency, and directory structure.

## Scope
- Tasks: ~3
- Layers: app (router, shell), features (placeholder screens)
- Risk: Low — standard GoRouter ShellRoute configuration with Material 3

---

## Problem Statement

The bootstrapped app (Proposal 000) has a single placeholder route. Feature proposals
(001 Recording, 007 History, Settings) need a navigation shell to plug into — a bottom
navigation bar, tab routing, and a defined flow for modal screens like transcript review.
Without this shell in place first, each feature proposal would make independent navigation
decisions, leading to inconsistent routing and duplicated shell code.

---

## Are We Solving the Right Problem?

**Root cause:** There is no navigation structure. The app has one route (`/`) pointing to
a placeholder. Features cannot integrate because there are no tabs, no shell, and no
defined navigation flows.

**Alternatives dismissed:**
- *Let each feature proposal add its own routes and build the shell incrementally:*
  Multiple proposals would need to modify `router.dart` with conflicting shell structures.
  Defining the shell once avoids merge conflicts and ensures a consistent navigation
  pattern.
- *Use Navigator 2.0 directly instead of GoRouter ShellRoute:* GoRouter is already a
  dependency from Proposal 000 and provides `ShellRoute` specifically for this use case.
  Raw Navigator 2.0 adds boilerplate without benefit.

**Smallest change?** Yes — this proposal defines the shell, tab routes, and the
recording-to-review flow. It uses placeholder screens that feature proposals replace with
real implementations.

---

## Goals

- Establish the bottom navigation shell with three tabs that feature screens plug into
- Define the recording-to-transcript-review navigation flow precisely
- Handle the first-launch state when API URL is not yet configured

## Non-goals

- No deep linking — MVP does not need URL-based navigation
- No custom theme or brand colors — Material 3 defaults are sufficient
- No transition animations beyond Material 3 defaults
- No onboarding flow — a single banner on the recording screen is enough

---

## User-Visible Changes

After this proposal, launching the app shows a bottom navigation bar with three tabs:
History, Record, and Settings. The Record tab is the default/home tab. Each tab shows a
placeholder screen with its name. If the API URL has not been configured, a Material
banner appears at the top of the Record screen: "Set up your API endpoint in Settings."
The banner includes a "Go to Settings" action button.

---

## Solution Design

### Bottom Navigation Structure

```
┌─────────────────────────────────────────┐
│                                         │
│         [Tab Content Area]              │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│   History    │   Record    │  Settings  │
│   (clock)    │   (mic)     │  (gear)    │
└─────────────────────────────────────────┘
```

Three tabs using `NavigationBar` (Material 3):
- **History** — `Icons.history`, route `/history`. Replaced by Proposal 007.
- **Record** — `Icons.mic`, route `/record`. Default tab. Replaced by Proposal 001.
- **Settings** — `Icons.settings`, route `/settings`. Replaced by a future settings proposal.

The Record tab is the center tab and the initial route on app launch.

### GoRouter Configuration

The router uses a `StatefulShellRoute.indexedStack` to preserve tab state across switches:

```
Contract: Router Structure

StatefulShellRoute.indexedStack
  ├── branches[0]: /history
  │     └── GoRoute('/history') → HistoryPlaceholderScreen
  ├── branches[1]: /record    (default, initialLocation)
  │     └── GoRoute('/record') → RecordPlaceholderScreen
  │           └── GoRoute('review') → TranscriptReviewPlaceholderScreen
  └── branches[2]: /settings
        └── GoRoute('/settings') → SettingsPlaceholderScreen

Shell widget: AppShellScaffold (Scaffold with NavigationBar)
```

Key configuration details:
- `initialLocation: '/record'` — app opens on the Record tab
- `StatefulShellRoute.indexedStack` — each branch maintains its own navigation stack so
  scrolling position and state are preserved when switching tabs
- The shell widget (`AppShellScaffold`) wraps the current branch's navigator in a
  `Scaffold` with a `NavigationBar` at the bottom
- `NavigationBar.selectedIndex` is driven by the shell route's `currentIndex`
- Tab switching calls `shellController.goBranch(index)`

### Navigation Flow: Recording to Transcript Review

```
/record (RecordScreen)
    │
    │  User completes recording + STT
    │
    ▼
/record/review (TranscriptReviewScreen)
    │  Pushed as a sub-route of /record
    │  Bottom nav remains visible
    │
    ├── Send → triggers sync, pops back to /record
    └── Cancel → pops back to /record
```

The transcript review screen is a **child route** of `/record`, not a modal dialog. This
keeps it within the Record branch's navigation stack. The bottom navigation bar remains
visible. When the user sends or cancels, the route pops back to `/record`.

Proposal 003 (Transcript Processing) will replace the placeholder review screen with the
real implementation. The route structure defined here ensures it has a well-defined place
to plug in.

### First-Launch Banner

When the API URL is not configured (empty or null in storage), the Record screen displays
a `MaterialBanner` at the top:

```
Contract: First-Launch Banner

Condition: apiUrlConfiguredProvider returns false
Widget: MaterialBanner
  Content: "Set up your API endpoint in Settings to sync your transcripts."
  Action: TextButton("Go to Settings") → navigates to /settings
  Dismissable: No — persists until API URL is configured
```

This proposal defines a simple `apiUrlConfiguredProvider` that **always returns `false`**
(banner always shown). Proposal 006 (Settings Screen) owns `shared_preferences` and
settings persistence. When 006 lands, it replaces this stub provider with a real
implementation that reads from `SharedPreferences`. This avoids 008 taking ownership of
a settings dependency it doesn't own.

### File Structure

```
lib/
  app/
    router.dart              # Modified — full ShellRoute config replaces placeholder
    app_shell_scaffold.dart  # New — Scaffold with NavigationBar
  features/
    recording/
      presentation/
        record_placeholder_screen.dart     # Placeholder with first-launch banner
        review_placeholder_screen.dart     # Placeholder for transcript review
    history/
      presentation/
        history_placeholder_screen.dart    # Placeholder
    settings/
      presentation/
        settings_placeholder_screen.dart   # Placeholder
  core/
    providers/
      api_url_provider.dart  # Stub provider returning false; replaced by 006 with real impl
```

### Placeholder Screens

Each placeholder screen is a `Scaffold` with a centered `Text` widget showing the screen
name (e.g., "Record", "History", "Settings"). These are temporary — each feature proposal
replaces its placeholder with the real implementation by updating the route's builder in
`router.dart`.

The Record placeholder additionally includes the first-launch banner logic (watching
`apiUrlProvider`).

---

## Affected Mutation Points

| File / Area | Change |
|------------|--------|
| `lib/app/router.dart` (from 000) | Replace single placeholder route with full `StatefulShellRoute.indexedStack` configuration |
| `lib/app/app.dart` (from 000) | No change — already uses `MaterialApp.router` with GoRouter |
| `lib/core/providers/api_url_provider.dart` | New stub provider (`apiUrlConfiguredProvider` returns `false`). Replaced by Proposal 006 with real SharedPreferences read. |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Create `AppShellScaffold` with `NavigationBar` (3 tabs: History, Record, Settings). Set up `StatefulShellRoute.indexedStack` in `router.dart` with three branches, each pointing to a placeholder screen. Set `initialLocation` to `/record`. Add `/record/review` as a child route of `/record` with a placeholder screen. Include widget test: app renders shell with 3 tabs, tapping each tab shows correct placeholder, default tab is Record. | app |
| T2 | Create stub `apiUrlConfiguredProvider` (returns `false`). Add `MaterialBanner` to the Record placeholder screen that appears when provider returns `false`, with a "Go to Settings" action that navigates to the Settings tab. Include widget test: banner appears when provider returns false, banner hidden when provider overridden to return true, tapping action navigates to Settings. | app, core/providers, features/recording |
| T3 | Implement tab state preservation verification and recording-to-review navigation flow. Verify that switching tabs preserves scroll/state in each branch (indexedStack behavior). Verify that navigating to `/record/review` shows the review placeholder and bottom nav stays visible, and that popping returns to `/record`. Include widget test: navigate to review and pop back, tab switch preserves state. | app, features/recording |

---

## Test Impact

### Existing tests affected
- `test/app/app_test.dart` (from 000) — may need update since the home screen is no longer
  a single placeholder but the shell with tabs. Update to verify the shell renders.

### New tests
- `test/app/app_shell_scaffold_test.dart` — shell renders 3 tabs, correct tab selected on launch, tab switching works
- `test/app/router_test.dart` — navigation to each route renders correct screen, `/record/review` is accessible
- `test/features/recording/record_placeholder_screen_test.dart` — first-launch banner visibility based on API URL state

---

## Acceptance Criteria

1. App launches and shows the Record tab as the default screen.
2. Bottom navigation bar displays three tabs: History, Record, Settings with correct icons.
3. Tapping each tab switches to the corresponding placeholder screen.
4. Switching tabs preserves the state of the previous tab (indexedStack behavior).
5. Navigating to `/record/review` shows the review placeholder screen with the bottom nav still visible.
6. Popping from `/record/review` returns to `/record`.
7. When `apiUrlConfiguredProvider` returns `false`, a MaterialBanner appears on the Record screen with "Go to Settings" action.
8. When `apiUrlConfiguredProvider` is overridden to return `true`, the MaterialBanner does not appear.
9. Tapping "Go to Settings" on the banner navigates to the Settings tab.
10. `flutter test` passes with all new and updated tests.
11. `flutter analyze` exits with zero issues.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `StatefulShellRoute.indexedStack` keeps all three tab widgets in memory simultaneously | Acceptable for 3 lightweight screens. If memory becomes an issue with heavy feature screens, individual proposals can add disposal logic. The indexedStack is the standard GoRouter approach for tab preservation. |
| Modifying `router.dart` from Proposal 000 may conflict with other proposals that also add routes | This proposal is sequenced to run before feature proposals. Feature proposals add sub-routes within the branches defined here, which are additive changes (no conflict with the shell structure). |
| Stub `apiUrlConfiguredProvider` always shows the banner until 006 replaces it | Acceptable — the banner is informative and non-blocking. It becomes conditional once 006 lands. |

---

## Known Compromises and Follow-Up Direction

### Placeholder screens instead of real features (V1 pragmatism)
Each tab renders a placeholder. Feature proposals (001, 007, settings) replace these one
at a time. This is intentional — the shell must exist before features can plug in. The
placeholders are deleted as each feature lands.

### No deep links
`GoRouter` supports deep linking out of the box, but this proposal does not define or test
any deep link behavior. URLs like `voiceagent://record` can be added in a follow-up when
there is a concrete use case (e.g., opening from a notification).

### No custom theme
Material 3 defaults are used throughout. A dedicated theming proposal can introduce brand
colors, typography, and component overrides once the functional MVP is complete.

### API URL check is a stub
The `apiUrlConfiguredProvider` always returns `false` (banner always shown). Proposal 006
replaces it with a real implementation reading from SharedPreferences. This avoids 008
taking ownership of a persistence dependency. When 006 lands, the provider should be moved to the
settings feature's domain layer. For now, the simple provider is sufficient and avoids
over-engineering.
