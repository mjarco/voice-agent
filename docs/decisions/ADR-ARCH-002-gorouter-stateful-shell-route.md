# ADR-ARCH-002: GoRouter with StatefulShellRoute navigation

Status: Accepted
Proposed in: P000, P008

## Context

The app uses a bottom navigation bar with three tabs (History, Record, Settings). Each tab must preserve its own navigation state when switching between tabs.

Flutter's built-in `Navigator` does not natively support multi-branch stateful navigation. The main contenders were:

- **GoRouter** — declarative routing with `StatefulShellRoute.indexedStack` for multi-tab state preservation.
- **AutoRoute** — similar capabilities but heavier, codegen-based.
- **Manual Navigator 2.0** — full control but substantial boilerplate.

## Decision

Use GoRouter with `StatefulShellRoute.indexedStack` and 3 tab branches. All routes are defined in `lib/app/router.dart`. Feature proposals replace placeholder screens in existing routes — they do not add new top-level routes.

Child routes (e.g. `/record/review`) stay within their parent branch so bottom nav remains visible.

## Rationale

GoRouter is the officially recommended routing package for Flutter. `StatefulShellRoute.indexedStack` preserves widget state across tab switches without manual state management. Declarative route definitions make the navigation structure visible in one file.

## Consequences

- Route ownership is centralized in `router.dart` — feature modules register screens there.
- Navigation arguments pass via GoRouter `extra` parameter (type-unsafe but simple).
- Adding a new tab requires modifying the shell route definition.
- `IndexedStack` keeps all tab subtrees in memory — acceptable for 3 tabs.
