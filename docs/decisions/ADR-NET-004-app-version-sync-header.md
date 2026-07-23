# ADR-NET-004: Report the installed app version via the X-App-Version sync header

Status: Accepted

## Context

There was no way to tell which voice-agent build was installed on a device
without a rebuild+reinstall. The in-app Settings tile was hardcoded (fixed in
#345), and nothing the app sent to personal-agent carried the version, so the
backend could not answer "what build is on the phone?" either.

The app already makes an authenticated `POST` to personal-agent on every
transcript sync (ADR-NET-002). That request is the natural carrier for a
version signal — no new endpoint, no polling.

## Decision

`ApiClient` attaches an `X-App-Version` header, valued with the installed
version in wire form `<version>+<build>` (e.g. `1.3.0+6`, mirroring
`pubspec.yaml`'s `version:` line), to **every** request it makes — the
transcript `POST`, `testConnection`, and the generic `request()` path.

- The value flows from `appVersionProvider` (the runtime `package_info_plus`
  read added in #345) through `apiClientProvider`, which passes
  `AppVersion.wire` into `ApiClient(appVersion: …)`.
- The provider is a `FutureProvider`; until it resolves, `appVersion` is null
  and the header is **omitted**. The client rebuilds with the header set once
  the value is available. Absence is a valid state, never an error.
- Header construction is centralised in `ApiClient._headers()` so Auth,
  Content-Type, and version stay consistent across call sites.

The backend side (capture, persistence, exposure) is the sibling change in
personal-agent (thought-agent#492, ADR there).

## Consequences

- **Backward-compatible both ways.** Old servers ignore the unknown header;
  old clients (no header) are recorded as "unknown" server-side. No coordinated
  deploy is required — the header is inert until the backend reads it.
- The version leaves the device on every sync. It is non-sensitive (the build
  number of an app the user installed) and goes only to the user's own
  configured backend over the existing authenticated channel.
- Cited by #346. Backend contract half: thought-agent#492.
