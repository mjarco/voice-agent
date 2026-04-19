# Proposal 020 — Navigation Restructure (5-Tab Layout)

## Status: Implemented

## Prerequisites
- P008 (App Navigation) — defines the current 3-tab shell with `StatefulShellRoute.indexedStack`; merged
- P025 (Shared API Client Layer) — shared models referenced by placeholder screens; implemented

## Scope
- Tasks: 3
- Layers: app (router, shell scaffold), features (minor: history screen app bar, settings access)
- Risk: Medium — changes navigation foundation; all existing screens must keep working; memory impact of 5-tab IndexedStack needs verification

---

## Problem Statement

The current navigation has 3 tabs: History, Record, Settings (P008). This was correct for an app whose only job was recording and syncing transcripts. With the addition of Agenda, Routines, Plan, and Chat features, the bottom navigation needs to accommodate more entry points.

The 3-tab layout cannot scale:

1. **No room for new features** — adding Agenda or Routines requires either replacing an existing tab (losing quick access to History/Settings) or nesting them as sub-screens (burying primary features).
2. **Wrong priority ordering** — History (transcript list) occupies a primary tab, but once Agenda and Plan exist, transcript history becomes a secondary concern. The user's day starts with "what's on my agenda" and "what are my active action items", not "what did I record yesterday".
3. **Settings as a tab wastes space** — Settings is visited rarely. It doesn't deserve a permanent bottom nav slot.

---

## Are We Solving the Right Problem?

**Root cause:** The 3-tab shell was designed for a recorder app. The app is evolving into a personal agent client. The navigation hierarchy must reflect the new primary workflows: reviewing agenda, managing routines, tracking action items, and having conversations.

**Alternatives dismissed:**

- *Drawer navigation:* Hides all destinations behind a hamburger menu. On mobile, bottom tabs are the standard pattern for 3–5 primary destinations. A drawer is appropriate for 6+ destinations or secondary navigation.
- *4 tabs (drop one feature):* Possible, but all four new features (Agenda, Routines, Plan, Chat) are primary workflows. Dropping one to keep 4 tabs means nesting it as a sub-screen, which reduces discoverability.
- *Tab bar + "More" tab:* The "More" pattern (iOS-style) is workable but adds an extra tap for features behind it. With exactly 5 primary features, 5 tabs is clean.
- *Keep History as a tab, put Settings in a drawer:* Gets to 4 tabs (History, Record, Agenda, Routines), but drops Plan and Chat from primary access. History is lower-priority than Plan.
- *Dynamic tab bar based on configured features:* Over-engineered. All users will want all features once they exist.

**Smallest change?** Replace the 3-branch `StatefulShellRoute` with a 5-branch one. Move History under Record as a child route. Move Settings to an app bar action. Add placeholder screens for the 4 new tabs.

---

## Goals

- Restructure bottom navigation from 3 tabs to 5 tabs: Agenda, Plan, Record, Routines, Chat
- Relocate History to a child route of Record (`/record/history`)
- Relocate Settings to a top-level route accessible from the app bar (gear icon)
- Add placeholder screens for Agenda, Plan, Routines, and Chat tabs
- Preserve all existing functionality — recording, history, settings, sync, hands-free, wake word

## Non-goals

- No implementation of Agenda, Plan, Routines, or Chat features — those are P021–P024
- No changes to `SyncWorker`, `RecordingController`, or `HandsFreeController`
- No new API calls — placeholder screens are static
- No changes to `AppConfig` or storage
- No changes to the Settings screen content — only its navigation location changes

---

## User-Visible Changes

1. **Bottom navigation bar** changes from `History | Record | Settings` to `Agenda | Plan | Record | Routines | Chat`. Record remains the default tab on app launch.
2. **History** is no longer a tab. Users access it via a clock/history icon in the Record screen's app bar.
3. **Settings** is no longer a tab. Users access it via a gear icon in the app bar of each primary tab screen (placeholders and RecordingScreen).
4. **Four new tabs** show placeholder screens with a brief description and "Coming soon" indicator until their respective proposals are implemented.
5. The offline connectivity banner continues to appear regardless of which tab is active.

---

## Solution Design

### New Route Structure

```
StatefulShellRoute.indexedStack (5 branches)
  Branch 0: /agenda             → AgendaPlaceholderScreen
  Branch 1: /plan               → PlanPlaceholderScreen
  Branch 2: /record             → RecordingScreen (existing)
              /record/history   → HistoryScreen (relocated from /history)
              /record/history/:id → TranscriptDetailScreen (relocated from /history/:id)
  Branch 3: /routines           → RoutinesPlaceholderScreen
  Branch 4: /chat               → ChatPlaceholderScreen

Top-level (outside shell):
  /settings                     → SettingsScreen (relocated from shell branch)
    /settings/advanced          → AdvancedSettingsScreen (existing)
```

### Router Configuration

```dart
final router = GoRouter(
  initialLocation: '/record',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShellScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: Agenda
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/agenda',
              builder: (context, state) => const AgendaPlaceholderScreen(),
            ),
          ],
        ),
        // Branch 1: Plan
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanPlaceholderScreen(),
            ),
          ],
        ),
        // Branch 2: Record (default)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) => const RecordingScreen(),
              routes: [
                GoRoute(
                  path: 'history',
                  builder: (context, state) => const HistoryScreen(),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return TranscriptDetailScreen(transcriptId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        // Branch 3: Routines
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/routines',
              builder: (context, state) => const RoutinesPlaceholderScreen(),
            ),
          ],
        ),
        // Branch 4: Chat
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) => const ChatPlaceholderScreen(),
            ),
          ],
        ),
      ],
    ),
    // Settings — outside shell (full-screen, no bottom nav)
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'advanced',
          builder: (context, state) => const AdvancedSettingsScreen(),
        ),
      ],
    ),
  ],
);
```

### AppShellScaffold Changes

The scaffold changes from 3 to 5 `NavigationDestination` items. The shell continues to provide **only** the bottom `NavigationBar` — no `AppBar`. Each screen manages its own `Scaffold` and `AppBar` (the current pattern from P008). This avoids nested scaffolds: the shell's `Scaffold` wraps the `navigationShell` body and bottom nav; each screen inside provides its own `Scaffold` with its own `AppBar`.

```
┌──────────────────────────────────────────────┐
│ [Screen's own AppBar]              [⚙ gear]  │
│                                              │
│  (active tab content)                        │
│                                              │
│                                              │
├──────────────────────────────────────────────┤
│  Agenda  │  Plan  │  Record  │ Routines │ Chat │
└──────────────────────────────────────────────┘
```

**Contract: Tab index mapping**

| Index | Path | Icon | Label |
|-------|------|------|-------|
| 0 | `/agenda` | `Icons.calendar_today` | Agenda |
| 1 | `/plan` | `Icons.checklist` | Plan |
| 2 | `/record` | `Icons.mic` | Record |
| 3 | `/routines` | `Icons.repeat` | Routines |
| 4 | `/chat` | `Icons.chat_bubble_outline` | Chat |

**App bar ownership:**

Each primary tab screen provides its own `AppBar` with a gear icon action (`context.push('/settings')`). This is the existing pattern (RecordingScreen and HistoryScreen already have their own `Scaffold` + `AppBar`). Placeholder screens follow the same pattern. Pushed child screens (HistoryScreen, TranscriptDetailScreen) keep their existing AppBars without a gear icon.

For the Record tab specifically, the `RecordingScreen` app bar also includes a history icon → `context.push('/record/history')`.

When feature screens replace placeholders (P021–P024), they can customize their own `AppBar` actions freely (e.g., Agenda adds a date picker, Plan adds a filter icon) without modifying the shell.

**IndexedStack memory consideration:**

5 branches means 5 widget subtrees in memory simultaneously. For placeholder screens (static text), this is negligible. When real features land (P021–P024), each tab will have its own state. This is acceptable: GoRouter's `IndexedStack` is the recommended approach for up to 5 tabs (per ADR-ARCH-002, to be updated to reflect the 5-tab change). Beyond 5, consider lazy loading.

### Placeholder Screens

Each placeholder is a minimal `StatelessWidget` in `lib/app/placeholders/`. They are temporary — each is replaced by a real feature screen when its proposal lands.

```dart
// lib/app/placeholders/agenda_placeholder_screen.dart
class AgendaPlaceholderScreen extends StatelessWidget {
  const AgendaPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Agenda', style: TextStyle(fontSize: 20)),
            SizedBox(height: 8),
            Text('Daily tasks and routine schedule',
                 style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
```

Same pattern for Plan, Routines, Chat — each with its own `Scaffold`, `AppBar` (with title and gear icon), and placeholder body content.

**Contract: Placeholder replacement**

When P021 (Agenda) lands, it replaces the `AgendaPlaceholderScreen` import in `router.dart` with the real `AgendaScreen`. The route path (`/agenda`) and branch index (0) remain unchanged. Same pattern for P022 (Routines → index 3), P023 (Plan → index 1), P024 (Chat → index 4).

### History Relocation

History moves from branch 0 (`/history`) to a child route of Record (`/record/history`). This means:

1. `HistoryScreen` is no longer a tab — it's a pushed route.
2. When viewing history, the bottom nav still shows Record as selected (history is within the Record branch).
3. The back button from History returns to the Record screen.
4. `TranscriptDetailScreen` moves to `/record/history/:id`.

**History access point:**

The Record screen (or the app bar when Record tab is active) shows a history icon (clock). Tapping it navigates to `/record/history`.

### Settings Relocation

Settings moves from branch 2 (`/settings`) to a top-level route outside the shell. This means:

1. Navigating to Settings via `context.push('/settings')` covers the bottom nav (full-screen).
2. The back button from Settings returns to whatever tab was active.
3. Advanced Settings remains a child route at `/settings/advanced`.
4. The gear icon in the app bar is visible on all primary tab screens (placeholders + RecordingScreen). Pushed child screens (HistoryScreen, TranscriptDetailScreen) do not get a gear icon — users navigate back to the tab to access Settings. This is acceptable because Settings access was previously one tab-switch away; now it is one back-tap + one gear-tap away from child screens.

### File Structure

```
lib/
  app/
    router.dart                        # Updated: 5 branches + /settings outside shell
    app_shell_scaffold.dart            # Updated: 5 destinations (no app bar — screens own their own)
    placeholders/
      agenda_placeholder_screen.dart   # New — temporary
      plan_placeholder_screen.dart     # New — temporary
      routines_placeholder_screen.dart # New — temporary
      chat_placeholder_screen.dart     # New — temporary
```

---

## Affected Mutation Points

| File / Symbol | Change |
|---------------|--------|
| `lib/app/router.dart` | Replace 3-branch shell with 5-branch shell. Move `/history` routes under `/record/history`. Move `/settings` outside shell. Add 4 placeholder screen imports. |
| `lib/app/app_shell_scaffold.dart` | Update `NavigationBar` from 3 to 5 destinations with correct icons and labels per the tab index mapping. No `AppBar` changes — the shell continues to provide only the bottom nav. |
| `lib/app/placeholders/agenda_placeholder_screen.dart` | New — placeholder widget. |
| `lib/app/placeholders/plan_placeholder_screen.dart` | New — placeholder widget. |
| `lib/app/placeholders/routines_placeholder_screen.dart` | New — placeholder widget. |
| `lib/app/placeholders/chat_placeholder_screen.dart` | New — placeholder widget. |
| `lib/features/history/history_screen.dart` | Change `context.push('/history/${item.id}')` to `context.push('/record/history/${item.id}')`. No other content changes. |
| `lib/features/recording/presentation/recording_screen.dart` | (1) Change three `context.go('/settings')` calls (lines 85, 142, 347) to `context.push('/settings')` — `context.go` to an outside-shell route destroys shell state. (2) Add history icon to the existing `AppBar` actions: `IconButton(icon: Icon(Icons.history), onPressed: () => context.push('/record/history'))`. (3) Add gear icon to `AppBar` actions: `IconButton(icon: Icon(Icons.settings), onPressed: () => context.push('/settings'))`. |
| `lib/features/settings/settings_screen.dart` | No route path changes needed — `context.push('/settings/advanced')` continues to work from the outside-shell Settings route. |
| `docs/decisions/ADR-ARCH-002-gorouter-stateful-shell-route.md` | (1) Update "3 tab branches" to "5 tab branches" and IndexedStack memory note to "acceptable for up to 5 tabs". (2) Add outside-shell route pattern: infrequently accessed screens (e.g., Settings) may be placed as top-level GoRoutes outside the shell; navigation must use `context.push()` (not `context.go()`) to preserve shell state; bottom nav is hidden on outside-shell routes. (3) Clarify that P020 establishes the 5-branch route structure and subsequent feature proposals (P021–P024) replace placeholder screens within it. |
| `CLAUDE.md` (Route Ownership table + Navigation section) | (1) Update route paths: `/history` → `/record/history`, `/settings` → top-level (outside shell). (2) Update tab count from 3 to 5 in both the Route Ownership table and the Navigation section. (3) Update Route Ownership table to list all 5 shell branches + `/settings` as outside-shell + `/record/history` and `/record/history/:id` as child routes. (4) Clarify "Feature proposals replace placeholder screens in existing routes" — P020 establishes the route structure; P021–P024 replace placeholders within it. |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Create 4 placeholder screens in `lib/app/placeholders/`: `AgendaPlaceholderScreen`, `PlanPlaceholderScreen`, `RoutinesPlaceholderScreen`, `ChatPlaceholderScreen`. Each is a `StatelessWidget` with its own `Scaffold` + `AppBar` (title + gear icon → `context.push('/settings')`) and a centered icon, title, and subtitle in the body. Write widget tests verifying each placeholder renders its title text and gear icon. | app |
| T2 | Restructure `router.dart`: replace the 3-branch `StatefulShellRoute` with a 5-branch version. Move History routes from `/history` and `/history/:id` to `/record/history` and `/record/history/:id`. Move Settings routes from the shell to a top-level `GoRoute` at `/settings` (outside the shell, with `advanced` child route). Update all placeholder and existing screen imports. Update `HistoryScreen`: change `context.push('/history/${item.id}')` to `context.push('/record/history/${item.id}')`. Update `RecordingScreen`: (1) change three `context.go('/settings')` calls to `context.push('/settings')`; (2) add history icon and gear icon to existing `AppBar` actions. Update `ADR-ARCH-002` to reflect 5-tab change. Update `CLAUDE.md` Route Ownership table. Write router tests verifying: initial location is `/record`, all 5 branch paths resolve, `/record/history/:id` resolves, `/settings` and `/settings/advanced` resolve, old `/history` path no longer resolves. | app |
| T3 | Update `AppShellScaffold`: change `NavigationBar` from 3 to 5 destinations with correct icons and labels per the tab index mapping. No `AppBar` changes — the shell continues to provide only the bottom nav (each screen owns its own `AppBar`). Verify that `SyncWorker`, `HandsFreeController`, and `ActivationController` providers are still watched. Verify offline snackbar still fires. Write widget tests covering: 5 destinations render, tab switching updates `currentIndex`. | app |

---

## Test Impact

### Existing tests affected

- `test/app/router_test.dart` — exists; must be updated for 5 branches, new route paths (`/history` → `/record/history`), and `/settings` as top-level outside shell.
- `test/app/app_shell_scaffold_test.dart` (if it exists) — must be updated for 5 destinations instead of 3.
- `test/features/settings/advanced_settings_screen_test.dart` — exists; tests VAD params strip navigation to `/settings/advanced`. Verify this still works with Settings outside the shell.
- `test/features/history/history_screen_test.dart` — does not exist. No test updates needed, but the route path change in `HistoryScreen` (`/history/:id` → `/record/history/:id`) should be covered by a new test or router test.
- Any test that navigates via `/history` must use `/record/history` instead.

### New tests

- `test/app/placeholders/agenda_placeholder_screen_test.dart` — renders icon, title, and gear icon.
- `test/app/placeholders/plan_placeholder_screen_test.dart` — renders icon, title, and gear icon.
- `test/app/placeholders/routines_placeholder_screen_test.dart` — renders icon, title, and gear icon.
- `test/app/placeholders/chat_placeholder_screen_test.dart` — renders icon, title, and gear icon.
- `test/app/router_test.dart` — (update existing) all 5 branch paths resolve, child routes resolve, settings resolves outside shell, `/record/history/:id` resolves.
- `test/app/app_shell_scaffold_test.dart` — 5 destinations, tab switching.

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes — all new and existing tests green.
3. App launches on `/record` (center tab, index 2). The bottom nav shows 5 items: Agenda, Plan, Record, Routines, Chat.
4. Tapping each tab shows the corresponding screen (4 placeholders + existing RecordingScreen).
5. Tapping the gear icon from any tab navigates to Settings via `context.push`. The bottom nav is hidden on the Settings screen. Back returns to the previous tab. Shell state is preserved.
6. On the Record tab, a history icon appears in the RecordingScreen's app bar. Tapping it navigates to History. The bottom nav remains visible (Record tab selected). Back returns to Record.
7. History → detail navigation works: `/record/history` → `/record/history/:id`. The old `/history` path no longer resolves.
8. Settings → advanced navigation works: `/settings` → `/settings/advanced`.
8a. Record → advanced settings shortcut works: VAD params strip on RecordingScreen pushes `/settings/advanced` directly. Bottom nav is hidden (outside shell). Back returns to Record tab.
9. Recording, hands-free mode, wake word activation, and sync continue to function exactly as before. The three "Go to Settings" buttons in RecordingScreen (banner, error state, hands-free error) use `context.push('/settings')` (not `context.go`).
10. Offline snackbar still appears when connectivity drops, regardless of active tab.
11. Tab switching preserves state within each branch (IndexedStack behavior).
12. The 4 placeholder screens display their own AppBar (with title and gear icon), icon, and subtitle text.
13. ADR-ARCH-002 is updated to reflect 5-tab layout. CLAUDE.md Route Ownership table is updated.

---

## Risks

| Risk | Mitigation |
|------|------------|
| 5-tab IndexedStack increases memory usage | Placeholder screens are trivially lightweight. When real features land, each will manage its own state lifecycle. Monitor memory with DevTools after P021–P024. If problematic, switch from IndexedStack to lazy-loaded branches (GoRouter supports this). |
| Users accustomed to 3-tab layout are disoriented | The center tab (Record) remains the default and keeps its mic icon. The change adds options without removing the primary workflow. |
| History as a child route of Record is harder to discover | The history icon in the app bar is visible whenever the Record tab is active. This is one tap instead of a tab switch — acceptable tradeoff for freeing a tab slot. |
| Settings outside the shell means no bottom nav on Settings | Intentional — Settings is a configuration screen, not a workflow. Full-screen with back button is the standard mobile pattern for settings. |
| Old `/history` deep links or GoRouter redirects break | No external deep links exist today. Internal navigation references are updated in T2. `flutter analyze` catches any broken route references at compile time (GoRouter path strings are not type-checked, but widget tests in T2 verify resolution). |

---

## Known Compromises and Follow-Up Direction

### Placeholder screens are static

The 4 new tabs show static placeholder content until P021–P024 land. This is intentional — the navigation structure is ready for features to plug into without another shell restructure.

### No lazy branch loading

IndexedStack keeps all 5 branch widget trees in memory. For 4 placeholders + 1 real screen, this is fine. If future features have heavy initialization (e.g., Chat with SSE connections), consider switching specific branches to lazy loading. GoRouter does not natively support per-branch lazy loading in `StatefulShellRoute.indexedStack`, but wrapping branch content in a `Builder` that checks `currentIndex` before building can achieve this.

### App bar is owned by individual screens, not by the shell

Each screen provides its own `Scaffold` + `AppBar` (continuing the existing pattern from P008). This means the gear icon is duplicated across 5 screens (4 placeholders + RecordingScreen), and the history icon is only in RecordingScreen. When feature screens replace placeholders (P021–P024), they inherit the responsibility for their own `AppBar` and can freely add custom actions (date picker for Agenda, filter icon for Plan) without modifying the shell. The duplication of the gear icon across screens is acceptable: it is a single `IconButton` and avoids the complexity of a shell-owned `AppBar` with per-screen delegation.

### No animation on tab switch

The default `IndexedStack` has no transition animation. This matches the existing behavior (P008) and is consistent with Material 3 bottom nav guidelines.
