# Manual test plan: the glasses drive the microphone mode

Design: [ADR-AUDIO-016](../decisions/ADR-AUDIO-016-glasses-drive-the-microphone-mode.md); contract:
glass-native's `docs/va-control-protocol.md`; workspace off-roadmap task
`2026-11-11-glasses-start-conversation`.

**Overall status:** in-progress — the owner ran it on 2026-11-11 and reported "jest ok" without
naming cases; T3 has its own evidence; T5 failed as Android forbids, and the page no longer offers
it (glass-native D6).

**Why now:** the commands come from another app as broadcasts, the microphone service may be started
from the background, and the page is seen only on the glasses; none of it can be checked off the
device.

**Time budget:** setup 5 minutes; T1–T7 with the glasses on, 15 minutes.

**What we are testing:** the page "Rozmowa" in glass-native shows voice-agent's mode and switches it:
Włącz (Listening), Pauza (Standby), Wyłącz (Off, also from Standby), and a change made on the phone
reaches the glasses.

Status legend: as in [`p040-agenda-notifications.md`](p040-agenda-notifications.md).

## Status summary

| Case | What | Status |
|---|---|---|
| T1 | "Rozmowa" is the last menu entry and shows the mode | owner's run 2026-11-11, not itemised |
| T2 | Włącz from Standby resumes listening | owner's run 2026-11-11, not itemised |
| T3 | Pauza from Listening goes to Standby, and the page follows | passed (2026-11-11, Pixel 11 Pro, Android 17, dev 1.32.0) |
| T4 | Wyłącz ends the session from Listening and from Standby | owner's run 2026-11-11, not itemised |
| T5 | Włącz from Off with voice-agent in the background starts a session | failed (2026-11-11, Pixel 11 Pro, Android 17, dev 1.32.0): Android refuses the service; documented limitation |
| T6 | A change made on the phone reaches the page | owner's run 2026-11-11, not itemised |
| T7 | voice-agent swiped away: the page says so | pending |

## Setup

### S1. The builds

**Status:** passed (2026-11-11, Pixel 11 Pro, Android 17, dev 1.32.0)

voice-agent first (it defines `<applicationId>.permission.MIC`), then glass-native, which asks for
it: `adb shell dumpsys package casa.jarco.glassnative | grep permission.MIC` shows `granted=true` for
the flavor installed. Installed the other way round, the permission is not granted and every command
goes unanswered (T7's message).

### S2. Reading what happens

**Status:** passed (2026-11-11)

`adb logcat -s GlassNative GlassesControl`: glass-native logs `VA command <c> → <status> <mode>` and
`VA mode <MODE>`; voice-agent logs `glass-native: <c> → <status> (mode <m>)`.

## Test cases

### T1. "Rozmowa" is the last menu entry and shows the mode

**Status:** owner's run 2026-11-11, not itemised

**Do:**
1. Open the glasses' menu; open "Rozmowa".

**Why:** ADR-AUDIO-016 (glass-native's page in the last menu slot).

**Expected:** the first row is `Nasłuch: włączony`, `Nasłuch: pauza` or `Nasłuch: wyłączony`,
matching the phone; rows to run are marked `»`.

**On failure:** `Nasłuch: brak odpowiedzi VA` means no answer: S1's order, or voice-agent not
installed.

### T2. Włącz from Standby resumes listening

**Status:** owner's run 2026-11-11, not itemised

**Do:**
1. Put voice-agent into Standby (notification's Pauza).
2. On the glasses, long-press `» Włącz`.

**Why:** ADR-AUDIO-016 item 2 (listening → Resume from Standby).

**Expected:** the page shows `Nasłuch: włączony` within a second; the notification shows listening;
logcat `VA command listening → accepted standby`, then `VA mode LISTENING`.

**On failure:** while push-to-talk records, Resume is not taken; check `_onGlassesCommand`.

### T3. Pauza from Listening goes to Standby, and the page follows

**Status:** passed (2026-11-11, Pixel 11 Pro, Android 17, dev 1.32.0): logcat
`VA command standby → accepted listening`, `VA mode STANDBY`, `PAGE va mode local/rozmowa shown`.

**Do:**
1. voice-agent listening; long-press `» Pauza`.

**Why:** ADR-AUDIO-016 items 2 and 3.

**Expected:** `Nasłuch: pauza`, rows `» Włącz`, `» Wyłącz`; the microphone released.

**On failure:** no `VA mode` line: the report back (`GlassesControl.report`) lacks glass-native's
SHOW permission.

### T4. Wyłącz ends the session from Listening and from Standby

**Status:** owner's run 2026-11-11, not itemised

**Do:**
1. From Listening, long-press `» Wyłącz`.
2. Włącz again (from the phone if T5 fails), Pauza, then `» Wyłącz` from Standby.

**Why:** the owner's answer of 2026-11-11 ("wyłącz mogła wyłączyć także standby").

**Expected:** both times `Nasłuch: wyłączony`; the session's notification is gone.

**On failure:** a mode that stays: `_onGlassesCommand` off branch.

### T5. Włącz from Off with voice-agent in the background starts a session

**Status:** failed (2026-11-11, Pixel 11 Pro, Android 17, dev 1.32.0): the owner: "gdy voice-agent
jest wyłączony to nie da się włączyć"; logcat `startForegroundService() not allowed … BFGS denied`
(uidState LAST). Documented limitation: glass-native now shows `Włącz w telefonie` in Off, with no
move (its D6, `VA_START_FROM_OFF = false`). Run again only if that constant is turned back on.

**Do:**
1. voice-agent Off, sent to the background (Home), screen on.
2. Long-press `» Włącz`.
3. Repeat with the screen locked.

**Why:** ADR-AUDIO-013 says a microphone foreground service cannot be created from the background;
this case is what decides whether the page offers Włącz in Off (`VA_START_FROM_OFF` in glass-native).

**Expected:** `Nasłuch: włączony`; `adb shell dumpsys audio` shows the recorder not silenced.

**On failure:** a session that starts but records silence, or a `ForegroundServiceStartNotAllowed`
in logcat: set `VA_START_FROM_OFF = false`, and the page says `Włącz w telefonie` in Off.

### T6. A change made on the phone reaches the page

**Status:** owner's run 2026-11-11, not itemised

**Do:**
1. With "Rozmowa" open on the glasses, press Pauza in the notification, then Wznów.

**Why:** ADR-AUDIO-016 item 3 (every mode change is reported).

**Expected:** the page follows each press within a second.

### T7. voice-agent swiped away: the page says so

**Status:** pending

**Do:**
1. Swipe voice-agent from recents; long-press `» Włącz`.

**Why:** the `blocked` status of the contract.

**Expected:** the notice `Voice Agent nie działa: otwórz go w telefonie.`; any tap dismisses it.

## When this plan is done

Must-pass: T1–T4, T6. T5 is Android-conditional: a refusal is a documented limitation and switches
the page to `Włącz w telefonie`, it does not reopen the work. T7 is a nice-to-have.
