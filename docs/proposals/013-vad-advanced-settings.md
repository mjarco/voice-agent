# Proposal 013 — VAD Advanced Settings Screen

## Status: Implemented

## Prerequisites
- P012 (Hands-Free Mode with Local VAD) — fully merged

## Scope
- Tasks: ~3
- Layers: core/config, domain (HandsFreeEngine + VadService interfaces), data (VadServiceImpl, HandsFreeOrchestrator), presentation (AdvancedSettingsScreen)
- Risk: Low — extends existing config + settings pattern, no new architecture

---

## Problem Statement

The VAD pipeline (Silero model + segmentation logic) contains five hardcoded
constants in two source files. In practice every recording environment is
different: a quiet room needs different thresholds than a noisy kitchen; a slow
speaker needs a longer hangover than a fast one. Currently there is no way to
adjust these values without recompiling the app.

The most reported symptom is "rwie wypowiedzi" — longer utterances are split
into multiple segments mid-sentence. The likely cause is `hangoverMs` being
shorter than the natural pauses in the user's speech. Without a UI, every
tuning attempt requires a code change, rebuild, and re-deploy.

---

## Are We Solving the Right Problem?

**Root cause:** The five VAD constants in `VadServiceImpl` and
`HandsFreeOrchestrator` are compile-time literals. There is no path from user
intent ("stop cutting my sentences") to a change in behaviour without a code
change.

**Alternatives dismissed:**
- *Auto-tune via ML:* Would require labelled data and a separate training
  pipeline. Massively out of scope; not the smallest fix.
- *Ship multiple named presets (Quiet / Normal / Noisy):* Simpler UI, but
  masks the underlying parameters, making it impossible to fine-tune for an
  edge case. The user has already asked for specific numeric control.
- *Hard-code better defaults and ship:* Already done (P012 + recent tweaks).
  Still insufficient — the right values differ per user and environment.

**Smallest change?** A settings screen with five sliders that persist to
SharedPreferences and are read at session-start time. No new architecture
needed — the existing `AppConfig` + `AppConfigService` + `AppConfigNotifier`
pattern handles persistence; passing values at `engine.start()` keeps the
engine stateless between sessions.

---

## Goals

- The user can tune the five VAD parameters from within the app, without
  recompiling.
- Changes take effect on the next hands-free session (not mid-session).
- Each parameter shows its current value and has a sensible default that can
  be restored with one tap.
- Parameters are persisted across app restarts.

## Non-goals

- Auto-tuning or adaptive VAD — not in scope.
- Exposing `maxSegmentMs` or `cooldownMs` — these are rarely the problem and
  exposing too many knobs increases cognitive load.
- Per-environment profiles or named presets — future work.
- Changing VAD parameters mid-session — too complex, not needed.

---

## User-Visible Changes

A new "Advanced (VAD)" entry appears at the bottom of the Settings screen.
Tapping it opens a dedicated `AdvancedSettingsScreen` (`/settings/advanced`)
with five labelled sliders and a "Reset to defaults" button. Changes are saved
immediately on slider release.

Additionally, the current VAD parameter values are shown in a compact one-line
strip directly below the hands-free toggle on the Recording screen, so the user
can confirm active settings at a glance without opening Advanced Settings:

```
Hands-free                     [toggle]
─────────────────────────────────────────
thr 0.40 · hang 500ms · min 400ms · pre 300ms
```

The strip is always visible (not only when HF is active) and tapping it
navigates to `/settings/advanced`. New values are picked up the next time
the user starts a session.

```
Settings
  ─────────────────────────────
  Advanced (VAD)           >
  ─────────────────────────────

Advanced (VAD)
  ─────────────────────────────
  Speech threshold         0.40
  [────●──────────────────────]  0.1 ─ 0.9

  Silence threshold        0.35
  [──●────────────────────────]  0.1 ─ 0.8

  Hangover                500 ms
  [───────●────────────────────] 100 ─ 2000 ms

  Min speech              400 ms
  [──────●─────────────────────] 100 ─ 1000 ms

  Pre-roll                300 ms
  [─────●──────────────────────] 100 ─  800 ms

              [ Reset to defaults ]
  ─────────────────────────────
```

---

## Solution Design

### VadConfig value class

A new `VadConfig` value class lives in `core/config/vad_config.dart`. It
carries the five tunable parameters with default values matching the current
hardcoded constants:

```
VadConfig {
  positiveSpeechThreshold: double  // default 0.40  range [0.1, 0.9]
  negativeSpeechThreshold: double  // default 0.35  range [0.1, 0.8]
  hangoverMs: int                  // default 500   range [100, 2000]
  minSpeechMs: int                 // default 400   range [100, 1000]
  preRollMs: int                   // default 300   range [100, 800]
}
```

`VadConfig` has a `const VadConfig.defaults()` named constructor, a `copyWith`,
a `clamp()` factory that clips all fields to their valid ranges (called by
`AppConfigService.load()` to guard against corrupted SharedPreferences values),
and `operator ==` / `hashCode` / `toString()` — required for slider comparison
(`_draft == VadConfig.defaults()`) and debug logging.

### AppConfig extension

`AppConfig` gains a non-nullable `vadConfig: VadConfig` field with default
`VadConfig.defaults()`. Its `copyWith` uses the standard nullable-parameter
pattern (no sentinel needed since the field is non-nullable):

```
AppConfig copyWith({
  ...,                              // existing fields unchanged
  VadConfig? vadConfig,
}) => AppConfig(
  ...,
  vadConfig: vadConfig ?? this.vadConfig,
);
```

`AppConfigService` persists each sub-field as a flat SharedPreferences key
(`vad_positive_threshold`, `vad_negative_threshold`, `vad_hangover_ms`,
`vad_min_speech_ms`, `vad_pre_roll_ms`), consistent with existing key style.
`AppConfigService.load()` reads all five keys, constructs a `VadConfig`, and
calls `.clamp()` before storing — so out-of-range stored values are silently
corrected to the nearest valid value rather than causing undefined VAD
behaviour.

`AppConfigNotifier` gains `updateVadConfig(VadConfig)`.

### Threading config into the pipeline

`HandsFreeEngine.start()` signature changes to:

```
Stream<HandsFreeEngineEvent> start({required VadConfig config})
```

`HandsFreeController.startSession()` reads `appConfigProvider` and passes
`appConfig.vadConfig` when calling `engine.start()`.

`HandsFreeOrchestrator` stores the config in a `VadConfig? _config` instance
field. The field is overwritten on every `start()` call (not cleared on
`stop()` — stale reads are impossible because `_doStart()` is only called from
`start()` which always sets `_config` first). `_doStart()` uses `_config!` for
frame threshold computation and passes it to `_vadService.init(_config!)`.
Three of the five `static const` literals are removed (`_preRollMs`, `_hangoverMs`, `_minSpeechMs`). `_maxSegmentMs` and `_cooldownMs` are **retained** as static consts — they are not exposed to the user (see Non-Goals and Known Compromises).

`VadService.init()` interface changes to `Future<void> init(VadConfig config)`.
`VadServiceImpl.init(VadConfig config)` stores `config` in a field and uses it
in two places:
1. `VadIterator.create(positiveSpeechThreshold: config.positiveSpeechThreshold, negativeSpeechThreshold: config.negativeSpeechThreshold, ...)`
2. `_onEvent`: the label is `prob >= config.positiveSpeechThreshold` (not the
   current hardcoded `0.5`). This ensures the user-configured speech threshold
   controls both the `VadIterator`'s internal hysteresis **and** the `VadLabel`
   returned to the orchestrator. These two uses must stay in sync; using two
   different thresholds would create contradictory classification signals.

### Route

`/settings/advanced` is a child route of `/settings` in GoRouter.
`AdvancedSettingsScreen` is a `ConsumerStatefulWidget` (sliders need local
ephemeral `_draft` state for smooth dragging; values are flushed via
`updateVadConfig(_draft)` on `onChangeEnd`).

Navigation from SettingsScreen uses `context.push('/settings/advanced')` —
not `context.go`, which would reset the navigation stack and remove the back
button.

---

## Affected Mutation Points

**Needs change:**
- `HandsFreeEngine.start()` — add `{required VadConfig config}` parameter
- `HandsFreeOrchestrator.start()` — store config; pass to `_doStart()`
- `HandsFreeOrchestrator._doStart()` — replace 3 static consts (`_preRollMs`, `_hangoverMs`, `_minSpeechMs`) with config values; retain `_maxSegmentMs` and `_cooldownMs`
- `VadService.init()` — add `VadConfig config` parameter
- `VadServiceImpl.init()` — store config; pass thresholds to `VadIterator.create()`; use `config.positiveSpeechThreshold` in `_onEvent`
- `HandsFreeController.startSession()` — read `vadConfig` from `appConfigProvider`, pass to `engine.start()`
- `AppConfig` — add `vadConfig` field + `copyWith` clause
- `AppConfigService.load()` — read 5 flat keys, construct + clamp `VadConfig`
- `AppConfigService` — add `saveVadConfig(VadConfig)` writing all 5 keys
- `AppConfigNotifier` — add `updateVadConfig(VadConfig)`

**New files (created by this proposal):**
- `lib/core/config/vad_config.dart` — new `VadConfig` value class
- `lib/features/settings/advanced_settings_screen.dart` — new `AdvancedSettingsScreen`

**Needs change (presentation/routing):**
- `settings_screen.dart` — add `ListTile` entry navigating to `/settings/advanced`
- `recording_screen.dart` — add `_VadParamsStrip` `ConsumerWidget` below `SwitchListTile` in `_HandsFreeSection`
- `router.dart` — add `GoRoute(path: 'advanced', ...)` as child of `/settings`

**No change needed:**
- `HandsFreeController` state machine — session lifecycle unchanged
- `SyncWorker`, `RecordingController`, history — unrelated

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | `VadConfig` value class (defaults, copyWith, clamp); extend `AppConfig` + `AppConfigService` + `AppConfigNotifier`; unit tests for load/save round-trip and clamp | core/config |
| T2 | Thread `VadConfig` through `HandsFreeEngine.start()`, `VadService.init()`, `HandsFreeOrchestrator`, `HandsFreeController`; fix `_onEvent` threshold; remove 3 static consts, retain `_maxSegmentMs`/`_cooldownMs`; update all affected tests | domain, data, presentation |
| T3 | `AdvancedSettingsScreen` with 5 sliders + reset button; `/settings/advanced` route; link from SettingsScreen; widget tests | presentation |

### T1 details

- `VadConfig` in `lib/core/config/vad_config.dart` — `const VadConfig.defaults()`, `copyWith`, `clamp()` factory, `operator ==`, `hashCode`, `toString()`
- Flat SharedPreferences keys: `vad_positive_threshold` (double), `vad_negative_threshold` (double), `vad_hangover_ms` (int), `vad_min_speech_ms` (int), `vad_pre_roll_ms` (int)
- `AppConfigService.saveVadConfig(VadConfig)` — writes all 5 keys in one call
- `AppConfigService.load()` — constructs VadConfig from prefs then calls `.clamp()`
- `AppConfigNotifier.updateVadConfig(VadConfig)` — calls saveVadConfig, updates state
- Tests: round-trip for all 5 fields; missing keys return defaults; clamp corrects out-of-range values

### T2 details

- `VadService` interface: `Future<void> init(VadConfig config)`
- `HandsFreeEngine` interface: `Stream<HandsFreeEngineEvent> start({required VadConfig config})`
- `VadServiceImpl`: store `VadConfig _config` on first `init()` call; use `_config.positiveSpeechThreshold` in `_onEvent` instead of hardcoded `0.5`
- `HandsFreeOrchestrator`: `VadConfig? _config`; overwritten in `start()`; `_doStart()` uses `_config!`; remove 3 `static const` literals (`_preRollMs`, `_hangoverMs`, `_minSpeechMs`); retain `_maxSegmentMs` and `_cooldownMs`
- `HandsFreeController.startSession()`: `final vadConfig = ref.read(appConfigProvider).vadConfig;` → `engine.start(config: vadConfig)`
- Update all three test files for `start(config: VadConfig.defaults())` signature: `test/features/recording/data/hands_free_orchestrator_test.dart`, `test/features/recording/presentation/hands_free_controller_test.dart` (`FakeHandsFreeEngine.start()` on line 43), `test/features/recording/presentation/recording_screen_hands_free_test.dart` (`FakeHfEngine.start()`) — these are compile-time breaks if missed
- Update `test/features/recording/data/vad_service_stub.dart` `FakeVadService.init()` for new `init(VadConfig)` signature — compile-time break if missed

### T3 details

- `lib/features/settings/advanced_settings_screen.dart` (flat in feature root, consistent with existing `settings_screen.dart`)
- Local `VadConfig _draft`; init from `appConfigProvider`; flush on `onChangeEnd`
- `_VadSlider` helper: label, formatted value display, min/max, step divisions
- "Reset to defaults": sets `_draft = VadConfig.defaults()`, calls `updateVadConfig`
- Route: `GoRoute(path: 'advanced', builder: AdvancedSettingsScreen)` as child of `/settings`
- SettingsScreen: `ListTile` navigating via `context.push('/settings/advanced')`
- **Recording screen VAD strip**: add a `_VadParamsStrip` **`ConsumerWidget`** to `recording_screen.dart`. It is inserted **between** the `SwitchListTile` and the `if (isOn) [...]` block in `_HandsFreeSection.build()` — **not inside** the `if (isOn)` block — so it is always visible regardless of whether HF is active. It reads `appConfigProvider` via `ref.watch`; renders one line of small text (`thr X.XX · hang XXXms · min XXXms · pre XXXms`); tapping calls `context.push('/settings/advanced')` from `BuildContext` inside `_VadParamsStrip`. Note: `_HandsFreeSection` remains `StatelessWidget` — only `_VadParamsStrip` needs `ConsumerWidget`.
- **Async config load**: `AdvancedSettingsScreen` is a `ConsumerStatefulWidget`. In `initState`, initialise `_draft` from `ref.read(appConfigProvider).vadConfig`. Then use `ref.listenManual(appConfigProvider, ...)` to update `_draft` on first real load, guarded by `_userHasEdited` flag so in-flight user changes are never overwritten. `_userHasEdited` is set to `true` in `onChangeEnd` of any slider, **before** calling `updateVadConfig`. The `listenManual` callback skips the update when `_userHasEdited` is already `true`.
- Widget tests: sliders render current config values; reset restores defaults and calls `updateVadConfig`; slider change calls `updateVadConfig` on release; VAD strip shows current values and is tappable

---

## Test Impact

### Existing tests affected

- `test/features/recording/data/hands_free_orchestrator_test.dart` — all `engine.start()` calls need `config: VadConfig.defaults()`; frame threshold constants derived from defaults (values unchanged)
- `test/features/recording/presentation/hands_free_controller_test.dart` — `FakeHandsFreeEngine.start()` signature update
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — `FakeHfEngine.start()` signature update
- Any `FakeVadService` or `vad_service_stub.dart` used in orchestrator tests — `init()` signature update to `init(VadConfig config)` (**compile-time break if missed**)
- `test/features/settings/settings_screen_test.dart` — add test that `ListTile` for Advanced (VAD) is present and navigates to `/settings/advanced`
- `test/features/recording/data/vad_service_impl_test.dart` — `init()` call needs `VadConfig` argument; the `_onEvent` callback is private and wired via FFI `setVadEventCallback`, so threshold behaviour cannot be unit-tested without hitting the real `VadIterator`. Update `init()` call sites; threshold correctness is verified by AC6 (manual/device).

### New tests

- `test/core/config/vad_config_test.dart` — defaults, copyWith, equality, clamp behaviour
- `test/core/config/app_config_service_test.dart` — extend existing tests with VAD round-trip + clamp on load
- `test/features/settings/advanced_settings_screen_test.dart` — slider rendering, reset, persist on release

```bash
flutter test test/core/config/
flutter test test/features/settings/advanced_settings_screen_test.dart
flutter test test/features/recording/
```

---

## Acceptance Criteria

1. `AdvancedSettingsScreen` is reachable from Settings via `context.push('/settings/advanced')` with a working back button.
2. Each of the 5 sliders shows the persisted value on open (or the default on first launch).
3. Moving a slider and releasing updates the displayed value immediately and persists it.
4. Closing and reopening Advanced Settings shows the last saved values.
5. Tapping "Reset to defaults" restores all sliders to `VadConfig.defaults()` values and persists them.
6. **(manual)** Starting a hands-free session after changing `positiveSpeechThreshold` uses the new value in `_onEvent` label classification (unit-testable) and in `VadIterator.create()` (device-only: set threshold to 0.9, confirm speech is no longer detected).
7. A SharedPreferences value outside the valid range (e.g. `vad_hangover_ms = 9999`) is silently clamped to the range boundary on load, not passed raw to the VAD pipeline.
8. The VAD strip on the Recording screen shows current parameter values and navigates to Advanced Settings on tap.
9. `flutter analyze` — no issues; `flutter test` — all tests pass.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `FakeVadService.init()` compile break in tests | Explicitly called out in T2 details and test impact; must be updated in same PR as interface change |
| `_onEvent` threshold change alters classification behaviour | The change from `0.5` to `config.positiveSpeechThreshold` (currently `0.4`) makes the label slightly more sensitive — matches user intent and is consistent with VadIterator config |
| `VadIterator.create()` args cannot be verified in unit tests | `VadIterator` is a FFI-backed singleton with no test injection seam. Verified manually on device: change `positiveSpeechThreshold` to an extreme value (e.g. 0.9), start a HF session, confirm speech is no longer detected. Acceptance criterion 6 is a manual verification step — no logging instrumentation needed. |

---

## Known Compromises and Follow-Up Direction

### Flat SharedPreferences keys (V1 pragmatism)
`VadConfig` is stored as 5 individual SharedPreferences keys rather than a
single serialised JSON blob. Consistent with existing `AppConfigService`
pattern. Migration to a single JSON key is straightforward if `AppConfig` grows.

### `maxSegmentMs` and `cooldownMs` not exposed
These two constants remain hardcoded (30 s and 1 s). Can be added to `VadConfig`
and the screen in a follow-up without any architectural change.

### No mid-session config reload
Config is captured at `engine.start()` time and is immutable for the session.
Deliberate — changing thresholds mid-frame would require resetting the VAD
state machine. Live-tuning would need a `reconfigure()` path on `HandsFreeEngine`.

### File placement of `AdvancedSettingsScreen`
Placed flat in `lib/features/settings/`, consistent with the existing
`settings_screen.dart`. The project directory structure convention prescribes
a `presentation/` subdirectory — neither file follows it. A future cleanup can
move both screens to `presentation/` together.
