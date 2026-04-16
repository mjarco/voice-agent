# ADR-ARCH-009: Provider scope promotion for background-active controllers

Status: Proposed
Proposed in: P019

## Context

Riverpod providers in this project are typically observed at screen scope — a screen widget calls `ref.watch()` or `ref.read()`, and the provider is alive only while that screen is mounted. P019 needs `HandsFreeController` to be alive at app scope (not just when `RecordingScreen` is mounted) so that activation-triggered sessions can start and run even when the user is not on the recording tab.

This requires promoting the provider observation from `RecordingScreen.initState()` to `AppShellScaffold`, changing the controller's lifecycle from screen-scoped to app-scoped.

## Decision

When a feature controller must be reactive across the full app lifecycle (not just when its screen is visible), the provider observation is promoted to `AppShellScaffold`. A provider qualifies for promotion when ALL of the following are true:

1. The controller must respond to events while its screen is not mounted (e.g., background activation, cross-feature triggers via core providers).
2. The controller's idle state has negligible resource cost (no active audio streams, no running timers, no open network connections).
3. The promoting change preserves existing screen-level behavior: if the screen previously called a method on mount (e.g., `startSession()`), that call remains but becomes idempotent when the controller is already active.

Controllers that are screen-scoped by default (the common case) should NOT be promoted preemptively. Promotion happens only when a concrete cross-screen or background use case requires it.

## Rationale

The alternative — instantiating the controller in a background service or separate isolate — conflicts with the keepalive-only isolate model (P019) where all Riverpod state lives in the main Dart isolate. Promoting the provider to `AppShellScaffold` is the simplest way to ensure the controller is alive when needed without introducing a parallel state management system.

## Consequences

- Promoted controllers live for the app's lifetime — memory cost of their idle state is permanent (but should be negligible per criterion 2).
- `AppShellScaffold` accumulates `ref.watch()` calls for promoted providers. If this grows beyond ~5 promoted providers, consider extracting a dedicated `AppLifecycleManager` widget to avoid bloating the scaffold.
- Screen-level `initState()` calls to the promoted controller must be made idempotent (early return if already in an active state).
- Tests must verify the controller works both when the screen is mounted and when it is not.
- The default remains screen-scoped. Promotion is an explicit, justified escalation — not a pattern to adopt broadly.
