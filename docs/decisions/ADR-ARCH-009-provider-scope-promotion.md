# ADR-ARCH-009: Provider scope promotion for cross-screen controllers

Status: Accepted
Proposed in: P019
Amended in: P026

## Context

Riverpod providers in this project are typically observed at screen scope — a screen widget calls `ref.watch()` or `ref.read()`, and the provider is alive only while that screen is mounted. P019 needed `HandsFreeController` to be alive at app scope (not just when `RecordingScreen` is mounted) so that activation-triggered sessions could start and run even when the user was not on the recording tab. P026 removes wake word activation, but `handsFreeControllerProvider` remains app-scoped because `AppShellScaffold.onDestinationSelected` calls `stopSession()`/`startSession()` during tab navigation — disposing the controller on tab switch would sever in-flight sessions mid-operation.

This requires promoting the provider observation from `RecordingScreen.initState()` to `AppShellScaffold`, changing the controller's lifecycle from screen-scoped to app-scoped.

## Decision

When a feature controller must be reactive across the full app lifecycle (not just when its screen is visible), the provider observation is promoted to `AppShellScaffold`. A provider qualifies for promotion when ALL of the following are true:

1. The controller must respond to events while its screen is not mounted (e.g., background activation, cross-feature triggers via core providers).
2. The controller's idle state has negligible resource cost (no active audio streams, no running timers, no open network connections).
3. The promoting change preserves existing screen-level behavior: if the screen previously called a method on mount (e.g., `startSession()`), that call remains but becomes idempotent when the controller is already active.

Controllers that are screen-scoped by default (the common case) should NOT be promoted preemptively. Promotion happens only when a concrete cross-screen or background use case requires it.

## Rationale (P026 amendment)

`handsFreeControllerProvider` remains app-scoped because `AppShellScaffold.onDestinationSelected` calls `stopSession()` when the user navigates away from the Record tab and `startSession()` when they return. Screen-scoping would dispose the controller on tab switch, severing the in-flight session and deleting the WAV-cleanup / job-drain machinery mid-operation.

Note: P019's secondary justification (cross-feature activation events forwarded via core providers) is gone — activation has been removed in P026. The single remaining justification (tab-switch lifecycle) still meets the three criteria in this ADR's Decision section.

## Consequences

- Promoted controllers live for the app's lifetime — memory cost of their idle state is permanent (but should be negligible per criterion 2).
- `AppShellScaffold` accumulates `ref.watch()` calls for promoted providers. If this grows beyond ~5 promoted providers, consider extracting a dedicated `AppLifecycleManager` widget to avoid bloating the scaffold.
- Screen-level `initState()` calls to the promoted controller must be made idempotent (early return if already in an active state).
- Tests must verify the controller works both when the screen is mounted and when it is not.
- The default remains screen-scoped. Promotion is an explicit, justified escalation — not a pattern to adopt broadly.
