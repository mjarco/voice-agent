# ADR-PLATFORM-007: Shared core boot helper for foreground and background isolates

Status: Proposed
Proposed in: P040

## Context

Until P040, all dependency construction lived in the foreground `app_main.dart` boot sequence and was injected into the widget tree via `ProviderScope` overrides. ADR-ARCH-007 codifies that pattern: SQLite, `AppConfigService`, `ApiClient`, and feature repositories are initialized before `runApp` so every consumer sees its dependency from the first frame.

P040 introduces a `workmanager` periodic background task whose entrypoint runs in a separate Dart isolate. That isolate has:

- no widget tree,
- no `ProviderScope`,
- no shared memory with the foreground process,
- no access to overrides registered in the foreground `runApp` call.

Without a shared bootstrap path, the two contexts drift: any future refactor that adds a dependency in the foreground graph will silently break the background isolate, and the breakage will surface only as intermittent failures on a device. P027 explicitly chose `flutter_foreground_task` over `workmanager` partly to avoid this class of problem; P040 accepts the isolate model under ADR-NET-002's third-amendment carve-out and therefore must solve the boot-parity problem.

Three approaches were considered:

- **Fresh `ProviderContainer()` in the isolate.** Compact code at the call site, but overrides registered in `main()` do not transfer across isolates, and re-creating overrides duplicates the boot logic. Worse, hidden hydration ceremony (provider chains that read SharedPreferences or SQLite eagerly) becomes a debugging trap.
- **Per-isolate copy-paste of the relevant init slice.** Works initially, drifts immediately. Caught only by manual device verification, which the team has limited bandwidth for.
- **Shared bootstrap helper returning a typed bundle.** Single source of truth for dep construction. Both the foreground init path and the isolate entrypoint call it. Compile-time and test-time gates detect drift.

## Decision

A single function `coreBoot()` in `core/background/workmanager_core_boot.dart` constructs the cross-cutting `core/`-layer dependency graph and returns a typed `CoreBootBundle`:

```dart
class CoreBootBundle {
  final StorageService storage;
  final AppConfigService config;
  final ApiClient api;
  final NotificationService notifications;   // already initialized
}

Future<CoreBootBundle> coreBoot();
```

`coreBoot()` does NOT construct feature-level objects. Feature wiring is composed by app-layer code on top of the core bundle (see `app/background/wire_agenda_for_background.dart` in P040). This keeps `core/background/` free of `features/` imports and respects ADR-ARCH-003.

Both runtime contexts use the helper:

- **Foreground** (`app_main.dart`): `await coreBoot()` → wire feature bundles → register them as `ProviderScope` overrides → `runApp`.
- **Background isolate** (`app/background/agenda_refresh_entrypoint.dart`): `await coreBoot()` → wire feature bundles → use them directly. No `ProviderContainer`.

A parity-gate unit test asserts that both paths construct dependencies through `coreBoot()` plus the shared `wire_*` helpers and nothing else. The test fails if any future refactor open-codes dependency construction in either path.

`ProviderContainer` is **not** used in background isolates. Tasks that need provider-based access patterns must be rewritten to consume the typed bundle directly, or they do not belong in a background isolate.

## Rationale

The decision moves drift detection from "device-only intermittent failure" to "CI test failure." That is the highest-value invariant for any code that runs in multiple execution contexts.

Returning a typed bundle (instead of, e.g., a `Map<String, dynamic>` or a service locator) keeps construction order explicit and gives the type checker work to do. ADR-DATA-008's wrapper-type pattern applies: a named record of related dependencies is easier to evolve than a positional tuple or a registry.

The "no `ProviderContainer` in isolates" rule is empirically grounded — provider chains that depend on overrides break silently when constructed in a fresh container, and discovering that on a locked device with no debugger is an unproductive way to spend a day.

The split between `coreBoot()` (core deps) and feature wiring helpers (in `app/`) is mandatory because of ADR-ARCH-003. `core/` cannot import `features/`; feature wiring is composed at the app layer.

## Consequences

- Any new feature that needs to be reachable from a background task must:
  1. Add its core-layer dependencies to `coreBoot()` if not already covered.
  2. Add a `wire_<feature>_for_background.dart` helper in `app/background/` that constructs feature-level objects from the core bundle.
  3. Update the parity-gate test to include the new helper.
- The parity-gate test is the only architectural enforcement. A reviewer must flag any new `app_main.dart` or isolate-entrypoint dep construction that bypasses these helpers.
- `coreBoot()` is async because `StorageService.initialize()` is async (ADR-ARCH-007). It must complete before any consumer reads from the bundle.
- Background tasks that need a `Ref` or any provider-based access pattern are not supported by this ADR — by design. If a future use case requires it, a separate ADR must justify it.
- iOS BGTask flakiness (BGAppRefreshTask is opportunistic) is independent of this ADR. The helper guarantees that *when* the task runs, it sees the same world the foreground does; it does not guarantee that the task runs on any particular cadence.
- The bundle is constructed fresh on every isolate spawn. Cold-start cost in the background isolate is the same as foreground cold-start (SQLite open + SharedPreferences `getInstance` + plugin init). This is informal observation, not a budget — measured if it ever matters; acceptable for hourly periodic tasks.
- Tests for new features must verify they construct correctly through `coreBoot()` + their wire helper, not via ad-hoc mocks.

## Related ADRs

- ADR-ARCH-003 (layered feature isolation) — `core/` cannot import `features/`; this ADR's split reflects that.
- ADR-ARCH-007 (async DB init before runApp) — extended in spirit: the "one place that knows the init order" principle now spans two runtime contexts.
- ADR-DATA-008 (wrapper type for collection with metadata) — `CoreBootBundle` follows this shape.
- ADR-NET-002 (foreground-only sync) — its P040 amendment authorizes the `workmanager` integration that motivates this ADR.
- ADR-NOTIF-001 (diff-based reconciliation) — `LocalNotificationService` is one of the dependencies constructed by `coreBoot()`. Its foreground/background asymmetry (singleton vs. fresh-per-spawn) hinges on this ADR's "no `ProviderContainer` in isolates" rule.
