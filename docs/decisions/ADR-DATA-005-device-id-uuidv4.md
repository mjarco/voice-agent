# ADR-DATA-005: Device ID as UUIDv4 in SharedPreferences

Status: Accepted
Proposed in: P004

## Context

Transcripts sent to the user's API include a `deviceId` field to identify the sending device. The device ID needs to be stable across app launches but doesn't need to be tied to hardware.

Options:

- **Hardware identifier** (IMEI, IDFA) — stable across reinstalls but requires platform permissions (iOS `AppTrackingTransparency`, Android `READ_PHONE_STATE`). Privacy-invasive.
- **UUIDv4 in SharedPreferences** — random, generated on first access, persists across launches. Lost on app data clear or reinstall.
- **UUIDv4 in flutter_secure_storage** — same as above but survives "Clear Data" on some platforms (iOS Keychain persists across reinstalls).

## Decision

Generate a UUIDv4 on first access and store it in `SharedPreferences` under the key `device_id`. The generation lives in `SqliteStorageService.getDeviceId()`.

## Rationale

A random UUID avoids hardware identifier permissions and privacy concerns (no IDFA dialog on iOS). `SharedPreferences` is sufficient — the device ID is not a secret, just a correlator. Losing it on reinstall is acceptable: the server gets a new device ID but no data is lost.

## Consequences

- No hardware identifier permissions required — no `AppTrackingTransparency` prompt on iOS.
- Clearing app data or reinstalling generates a new device ID — the server may see duplicate devices for the same physical device.
- The device ID is stored in `SharedPreferences` (plaintext) not `flutter_secure_storage` — it's a correlator, not a credential.
- `getDeviceId()` lives in `StorageService` rather than `AppConfigService` — a boundary decision that could be revisited.
