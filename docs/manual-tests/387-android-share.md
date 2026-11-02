# Manual test: voice-agent#387 — the Android share menu

**Issue:** [voice-agent#387](https://github.com/mjarco/voice-agent/issues/387)
**Overall status:** **pending** — no case yet executed on a physical device.
**Why now:** the share intent, `launchMode` and task behaviour exist only on a device; `flutter test` covers the Dart routing, not these.
**Time budget:** ~15 min, Android only.
**What we are testing:** selected text from the browser reaches a saved pin with the app closed and running, it arrives once, and `singleTask` keeps one app instance without breaking the other ways in.

## Status legend

As in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Install on device | pending |
| T1 | App closed: selected text reaches a saved pin | pending |
| T2 | App running: selected text reaches a saved pin | pending |
| T3 | A page without a selection gives its link | pending |
| T4 | A share arrives once | pending |
| T5 | A share joins a form with a draft | pending |
| T6 | One app instance | pending |
| T7 | Hands-free survives a share | pending |
| T8 | Icon and notification still open the app | pending |

## Setup

### S1 — Install on device

**Status:** pending

`make install-android` from the worktree of the branch: stable flavor, on the Pixel, against production.

## Test cases

### T1 — App closed: selected text reaches a saved pin

**Status:** pending

**Do:**
1. Remove Voice Agent from recents.
2. In Chrome, select text and tap Share → Voice Agent.
3. Wait for the title, tap Save.

**Why:** criterion 1 of the readiness; the cold channel of ADR-PLATFORM-008.

**Expected:** the app starts on "New pin" with the text in the form. After Save the pin is on the Pins screen.

**On failure:** no Voice Agent in the menu: the `SEND` filter in `AndroidManifest.xml`. App opens on Record: `pendingSharedTextProvider` in `app_main.dart`, or `takeInitialText` answering null.

### T2 — App running: selected text reaches a saved pin

**Status:** pending

**Do:**
1. Open Voice Agent on the Agenda tab, then go to Chrome without closing it.
2. Select text and tap Share → Voice Agent.
3. Tap Save.

**Why:** criterion 1 of the readiness; the warm channel of ADR-PLATFORM-008.

**Expected:** "New pin" with the text, over Agenda. After Save you are on Agenda, and the pin is on the Pins screen.

**On failure:** app comes up with no form: `onNewIntent` in `MainActivity.kt`, `sharedTextStreamProvider` in `app.dart`.

### T3 — A page without a selection gives its link

**Status:** pending

**Do:**
1. In Chrome, open a page and tap Share in the menu, with nothing selected.
2. Pick Voice Agent.

**Why:** the issue: a link is saved as text.

**Expected:** the form holds the page's address as text.

**On failure:** `EXTRA_TEXT` reading in `ShareBridge.kt`.

### T4 — A share arrives once

**Status:** pending

**Do:**
1. Share a text. On the form, rotate the phone.
2. Go Back to the Pins screen, Home, then open Voice Agent from recents.
3. Share the same text again and Back without saving; repeat once.

**Why:** a redelivered intent must not open the form again, and a repeated share must not be swallowed.

**Expected:** step 1 keeps one form. Step 2 opens no form. In step 3 the form opens both times.

**On failure:** `savedInstanceState` in `MainActivity.kt`, `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` in `ShareBridge.kt`; the `SharedText` wrapper for a swallowed repeat.

### T5 — A share joins a form with a draft

**Status:** pending

**Do:**
1. Pins, "+", type a text, then go to Chrome without leaving the form.
2. Share a text to Voice Agent.

**Why:** two forms must not write one draft (voice-agent#391).

**Expected:** one form, "Draft restored", your text, an empty line, the shared text. One Back leaves the form. Back, then "+", shows the same joined text.

**On failure:** `_openSharedText` in `app.dart` (`pushReplacement`).

### T6 — One app instance

**Status:** pending

**Do:**
1. With the app running, share from Chrome.
2. Open recents.

**Why:** `singleTask`: a second copy would hold a second Flutter engine.

**Expected:** one Voice Agent card, next to Chrome's. `adb shell dumpsys activity activities` lists one `MainActivity`.

**On failure:** `launchMode` in `AndroidManifest.xml`.

### T7 — Hands-free survives a share

**Status:** pending

**Do:**
1. Start a hands-free session on Record.
2. Go to Chrome and share a text to Voice Agent.
3. Save the pin.

**Why:** the form is pushed, not `go`: the session lives under it.

**Expected:** the session keeps running, and after Save you are on Record with it still on.

**On failure:** `push` in `_openSharedText`.

### T8 — Icon and notification still open the app

**Status:** pending

**Do:**
1. Open the app, leave it on Routines, Home, tap the icon.
2. With the app in the background, tap a routine or agenda notification.

**Why:** `launchMode` changes every way into the activity.

**Expected:** step 1 returns to Routines, not to a fresh start. Step 2 opens the notification's screen in the same app.

**On failure:** `launchMode` in `AndroidManifest.xml`.

## When this plan is done

T1, T2, T4, T6, T7 and T8 are must-pass. T3 and T5 are must-pass too, on Chrome; another browser giving a different link format is a known limitation, not a failure.
