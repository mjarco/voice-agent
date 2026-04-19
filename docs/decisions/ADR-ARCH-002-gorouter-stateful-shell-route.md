# ADR-ARCH-002: GoRouter with StatefulShellRoute navigation

Status: Accepted
Proposed in: P000, P008
Updated in: P020

## Context

The app uses a bottom navigation bar with five tabs (Agenda, Plan, Record, Routines, Chat). Each tab must preserve its own navigation state when switching between tabs.

Flutter's built-in `Navigator` does not natively support multi-branch stateful navigation. The main contenders were:

- **GoRouter** — declarative routing with `StatefulShellRoute.indexedStack` for multi-tab state preservation.
- **AutoRoute** — similar capabilities but heavier, codegen-based.
- **Manual Navigator 2.0** — full control but substantial boilerplate.

## Decision

Use GoRouter with `StatefulShellRoute.indexedStack` and 5 tab branches. All routes are defined in `lib/app/router.dart`. P020 establishes the 5-branch route structure; subsequent feature proposals (P021–P024) replace placeholder screens within it — they do not add new top-level routes.

Child routes (e.g. `/record/history`) stay within their parent branch so bottom nav remains visible.

Infrequently accessed screens (e.g., Settings) may be placed as top-level GoRoutes outside the shell. Navigation to outside-shell routes must use `context.push()` (not `context.go()`) to preserve shell state. Bottom nav is hidden on outside-shell routes.

## Rationale

GoRouter is the officially recommended routing package for Flutter. `StatefulShellRoute.indexedStack` preserves widget state across tab switches without manual state management. Declarative route definitions make the navigation structure visible in one file.

## Consequences

- Route ownership is centralized in `router.dart` — feature modules register screens there.
- Navigation arguments pass via GoRouter `extra` parameter (type-unsafe but simple).
- Adding a new tab requires modifying the shell route definition.
- `IndexedStack` keeps all tab subtrees in memory — acceptable for up to 5 tabs. Beyond 5, consider lazy-loaded branches.
- Using `context.go()` to an outside-shell route destroys shell state (all tab branches are reset). Always use `context.push()` for outside-shell navigation.
