# ADR-PLATFORM-008: Two-channel cross-app-entry deep link with one-shot + stream invariant

Status: Proposed
Proposed in: P040

## Context

P040 introduces the app's first non-UI entry vector: a notification tap that may launch the app from a cold (force-quit) state or wake it from a warm (backgrounded) state. The `flutter_local_notifications` plugin exposes these as two distinct mechanisms with different timing requirements:

- `getNotificationAppLaunchDetails()` — returns the payload of the notification that launched the app, if any. Must be called before `runApp`; after that point, the cold-start payload is unrecoverable.
- `onDidReceiveNotificationResponse` — a callback registered during plugin initialization; fires for every tap *after* registration.

A naive implementation can either:

- Lose the cold-start payload by registering the callback after the plugin has already discarded it.
- Deliver the payload twice — once via `getNotificationAppLaunchDetails()` (read during init) and once via `onDidReceiveNotificationResponse` (if the callback is registered before the cold-start read).

Both failure modes cause user-visible bugs: missed deep links land on the default tab, double-delivered taps trigger duplicate navigation.

Future cross-app-entry mechanisms in the project have the same shape:

- URL handlers (universal links / app links) — cold start vs. warm-path callback.
- OAuth callbacks — cold redirect-handling vs. in-app token receipt.
- Share-target intents (Android) — cold launch with `Intent.EXTRA_STREAM` vs. warm `ACTION_SEND`.
- **Siri Shortcuts intents** — particularly relevant given [[wake_word_dropped]] designates Siri Shortcuts as the voice-agent activation method.

Each of these will benefit from a single, documented pattern rather than re-deriving the cold/warm coordination per feature.

## Decision

Cross-app-entry payloads flow through **two Riverpod-backed channels with a single invariant**:

1. **`pendingDeepLinkProvider`** — `StateProvider<String?>` in `core/providers/deep_link_providers.dart`. Populated *before* `runApp` from the platform's "launched-from-X" API (in P040: `getNotificationAppLaunchDetails()`). **Consumed exactly once** on first frame by `App.build()`'s `addPostFrameCallback`:
   - If the provider holds a value: `router.go(value)`, then `ref.read(provider.notifier).state = null`.
   - If null: no-op.
   This provider is the sole authority for the cold-start payload.

2. **`notificationTapStreamProvider`** — `StreamProvider<String>` in the same file (or sibling providers for non-notification entry vectors). Backed by a `StreamController<String>` that the platform callback (`onDidReceiveNotificationResponse` for notifications; analogous for URL handlers, etc.) writes to. **Registered after** the cold-start read has returned, ensuring the cold-start payload is never observed on this channel. `App` subscribes via `ref.listen` and routes for every emission.

**The invariant**: a single deep-link payload reaches exactly one of the two channels — never both, never neither (except for the documented init-window edge case below).

## Rationale

Cold start and warm path have **fundamentally different lifecycles**:

- Cold-start payload is a one-shot value present at the moment of process spawn; the platform API to retrieve it is a single-call.
- Warm-path payloads are a continuous stream over the app's lifetime; the platform API is a registered callback.

Forcing them into a single channel either loses information (a stream cannot represent "I was launched by X" — the value pre-exists subscription) or duplicates information (a one-shot value that also fires on the stream means consumers must de-dup).

Two providers with a written-down invariant is the smallest representation that captures the semantic difference. The invariant is checkable by reading three short pieces of code (cold-start read in `app_main.dart`, post-frame consumption in `App.build()`, callback registration in `LocalNotificationService.init()`); no test required.

Placing both providers in `core/providers/` (per ADR-ARCH-008) keeps the deep-link concern decoupled from the feature that consumes the payload. Any feature can subscribe; the producer (e.g., `LocalNotificationService`) does not need to know who reads.

**One-shot consumption via `StateProvider.notifier.state = null`** is preferred over auto-disposing providers because:

- The provider must survive until first frame, which is after `runApp` returns; auto-dispose with no listeners would dispose it prematurely.
- Explicit null-set is auditable in code review.
- Re-running the consumption logic is safe — if the value is already null, the callback no-ops.

**Registering the warm-path callback after the cold-start read** is a temporal coupling that the ADR makes explicit. `LocalNotificationService.init()` (and any analogous adapter for future entry vectors) must document this ordering in its API contract.

## Consequences

- The init-window edge case is acceptable: a notification arriving in the narrow window between `getNotificationAppLaunchDetails()` returning null and `onDidReceiveNotificationResponse` being registered will not be delivered to either channel. The window is <100 ms during boot, untestable in practice, and recoverable by re-tapping the notification. Manual verification covers cold and warm; the init-window case is documented and not tested.
- Future cross-app-entry mechanisms (URL handlers, OAuth callbacks, share-target intents, Siri Shortcuts) **must** reuse this pattern:
  1. A `StateProvider<T?>` in `core/providers/` for the boot-time payload, consumed once on first frame.
  2. A `StreamProvider<T>` (or `Stream<T>` exposed via a Provider) for runtime taps.
  3. The platform adapter registers its warm-path callback only after reading the boot-time payload.
- The two providers in P040 are notification-specific (`pendingDeepLinkProvider`, `notificationTapStreamProvider`). When a second entry vector lands, either rename them (and the file) to a generic shape (e.g., `deepLinkProviders.dart` with type-tagged payloads) or add sibling pairs (e.g., `pendingUrlLinkProvider`, `urlLinkStreamProvider`). The choice depends on whether routing logic differs by source.
- `App.build()` becomes responsible for one consumption per provider. If three boot-time providers exist (notification + URL + share-target), `App.build()` reads three in sequence in `addPostFrameCallback`. Acceptable.
- Tests covering the cold path must override `pendingDeepLinkProvider` with a non-null value and verify `router.go` is called once. Tests covering the warm path emit to the stream and verify routing. The init-window case is not testable.
- This ADR does not constrain *what* the payload contains beyond "routable string." For payloads with structured data (e.g., a `recordId` to mark done from the notification), wrap the payload string in a small `DeepLink` value type and parse in the consumer. P040 uses the route path directly (`/agenda`) because the only action is navigation.

## Related ADRs

- ADR-ARCH-008 (ephemeral cross-feature state) — establishes `core/providers/` as the canonical location for these providers.
- ADR-ARCH-002 (gorouter stateful shell route) — routing target for deep links is a GoRouter path; the consumer (`App.build()`) calls `router.go(path)`.
- ADR-NOTIF-001 (diff-based reconciliation with ID partitioning) — defines the producer (`LocalNotificationService`) that populates these channels.
- ADR-OBS-001 (dev-flavor telemetry singleton) — if a future entry vector wants telemetry on cold-start payloads, the consumption point in `App.build()` is the natural span boundary.
