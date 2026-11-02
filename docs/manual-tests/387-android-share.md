# Manual test: voice-agent#387 — the Android share menu

**Issue:** [voice-agent#387](https://github.com/mjarco/voice-agent/issues/387)
**Overall status:** **passed** — T1–T3 by the owner, T4–T7 and T8 step 1 over wireless adb; T8 steps 2 and 3 skipped on the owner's word.
**Why now:** the share intent, `launchMode` and task behaviour exist only on a device; `flutter test` covers the Dart routing, not these.
**Time budget:** ~15 min, Android only.
**What we are testing:** selected text from the browser reaches a saved pin with the app closed and running, it arrives once, and `singleTask` keeps one app instance without breaking the other ways in.

## Status legend

As in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Install on device | passed |
| T1 | App closed: selected text reaches a saved pin | passed |
| T2 | App running: selected text reaches a saved pin | passed |
| T3 | A page without a selection gives its link | passed |
| T4 | A share arrives once | passed |
| T5 | A share joins a form with a draft | passed |
| T6 | One app instance | passed |
| T7 | Hands-free survives a share | passed |
| T8 | Icon and notification still open the app | passed, steps 2–3 skipped |

## Setup

### S1 — Install on device

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — `1.15.0+30` from `87283b8`

`make install-android` from the worktree of the branch: stable flavor, on the Pixel, against production.

## Test cases

### T1 — App closed: selected text reaches a saved pin

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — run by the owner, from Chrome

**Do:**
1. Remove Voice Agent from recents.
2. In Chrome, select text and tap Share → Voice Agent.
3. Wait for the title, tap Save.

**Why:** criterion 1 of the readiness; the cold channel of ADR-PLATFORM-008.

**Expected:** the app starts on "New pin" with the text in the form. After Save the pin is on the Pins screen.

**On failure:** no Voice Agent in the menu: the `SEND` filter in `AndroidManifest.xml`. App opens on Record: `pendingSharedTextProvider` in `app_main.dart`, or `takeInitialText` answering null.

### T2 — App running: selected text reaches a saved pin

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — run by the owner, from Chrome

**Do:**
1. Open Voice Agent on the Agenda tab, then go to Chrome without closing it.
2. Select text and tap Share → Voice Agent.
3. Tap Save.

**Why:** criterion 1 of the readiness; the warm channel of ADR-PLATFORM-008.

**Expected:** "New pin" with the text, over Agenda. After Save you are on Agenda, and the pin is at the top of the Pins screen, also when Pins was opened earlier in this run.

**On failure:** app comes up with no form: `onNewIntent` in `MainActivity.kt`, `sharedTextStreamProvider` in `app.dart`.

### T3 — A page without a selection gives its link

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — run by the owner, from Chrome

**Do:**
1. In Chrome, open a page and tap Share in the menu, with nothing selected.
2. Pick Voice Agent.

**Why:** the issue: a link is saved as text.

**Expected:** the form holds the page's address as text.

**On failure:** `EXTRA_TEXT` reading in `ShareBridge.kt`.

### T4 — A share arrives once

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — step 1 keeps one form; rotation does not recreate the activity (`configChanges` covers `orientation`), so step 2 is the case that reaches the guard. Shares sent by `am start`, same `SEND` intent, without Chrome's chooser

**Do:**
1. Remove Voice Agent from recents, then share a text from Chrome. On the form, rotate the phone.
2. Back until the form is gone, then Home. Run `adb shell am kill com.voiceagent.voice_agent`, and open Voice Agent from recents.
3. Share the same text again and Back without saving; repeat once.

**Why:** a redelivered intent must not open the form again, and a repeated share must not be swallowed. Step 2 needs the process gone, or the guard never runs.

**Expected:** step 1 keeps one form. Step 2 opens no form, though the app starts again. In step 3 the form opens both times.

**On failure:** `savedInstanceState` in `MainActivity.kt`, `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` in `ShareBridge.kt`; the `SharedText` wrapper for a swallowed repeat.

### T5 — A share joins a form with a draft

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — share sent by `am start` with Chrome in front

**Do:**
1. Pins, "+", type a text, then go to Chrome without leaving the form.
2. Share a text to Voice Agent.

**Why:** two forms must not write one draft (voice-agent#391).

**Expected:** one form, "Draft restored", your text, an empty line, the shared text. One Back leaves the form. Back, then "+", shows the same joined text.

**On failure:** `_openSharedText` in `app.dart` (`pushReplacement`).

### T6 — One app instance

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — one `MainActivity`, one task, one recents card; `launchMode=2` in the APK manifest

**Do:**
1. With the app running, share from Chrome.
2. Open recents.

**Why:** `singleTask`: a second copy would hold a second Flutter engine.

**Expected:** one Voice Agent card, next to Chrome's. `adb shell dumpsys activity activities` lists one `MainActivity`.

**On failure:** `launchMode` in `AndroidManifest.xml`.

### T7 — Hands-free survives a share

**Status:** passed (2026-11-02, Pixel 11 Pro, Android 17) — share sent by `am start` with Chrome in front; the session kept listening, and the pin was saved

**Do:**
1. Start a hands-free session on Record.
2. Go to Chrome and share a text to Voice Agent.
3. Save the pin.

**Why:** the form is pushed, not `go`: the session lives under it.

**Expected:** the session keeps running, and after Save you are on Record with it still on.

**On failure:** `push` in `_openSharedText`.

### T8 — Icon and notification still open the app

**Status:** step 1 passed (2026-11-02, Pixel 11 Pro, Android 17; launcher intent via `monkey`, same process and screen). Steps 2 and 3 skipped (the owner's word, 2026-11-02): a notification tap and the permission dialog stayed unverified on a device.

**Do:**
1. Open the app, leave it on Routines, Home, tap the icon.
2. With the app in the background, tap a routine or agenda notification.
3. Open a screen that shows a system permission dialog, Home, tap the icon.

**Why:** `launchMode` changes every way into the activity.

**Expected:** step 1 returns to Routines, not to a fresh start. Step 2 opens the notification's screen in the same app. In step 3 the dialog is gone: `singleTask` closes what stands above the app, and this is accepted.

**On failure:** `launchMode` in `AndroidManifest.xml`.

## When this plan is done

T1, T2, T4, T6, T7 and T8 are must-pass. T3 and T5 are must-pass too, on Chrome; another browser giving a different link format is a known limitation, not a failure.
