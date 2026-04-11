# ADR-PLATFORM-003: Microphone permission via record package, not permission_handler

Status: Accepted
Proposed in: P001

## Context

The app needs microphone permission to record audio. Two approaches:

- **`permission_handler`** — multi-step flow: `Permission.microphone.request()` -> check `isGranted` -> check `isPermanentlyDenied`. Full control over the permission lifecycle. Heavy package with native code for every permission type.
- **`record` package's `hasPermission()`** — single call that both checks and requests permission. Simpler but cannot distinguish between "never asked" and "permanently denied".

## Decision

Use `AudioRecorder.hasPermission()` from the `record` package as the primary permission mechanism. The `permission_handler` package is a dependency only for `openAppSettings()` — the "Open Settings" button shown when permission is denied.

`RecordingServiceImpl.requestPermission()` delegates directly to `_recorder.hasPermission()`.

## Rationale

The `record` package's `hasPermission()` method handles the common path (request on first call, check on subsequent calls) in one call. Since the app's only permission is the microphone and the `record` package already includes the native permission code, using it avoids duplicating permission logic. The inability to distinguish "never asked" from "permanently denied" is mitigated by always offering "Open Settings" as a fallback.

## Consequences

- Two permission-related packages in pubspec.yaml (`record` for the actual permission, `permission_handler` for `openAppSettings()`).
- Cannot show different UI for "first time asking" vs. "previously denied" — always shows the same error with a Settings button.
- If additional permissions are needed in the future (e.g., location, notifications), `permission_handler` is already available.
