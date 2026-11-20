# Manual test plan: held listening from a button (ADR-AUDIO-017)

**Design:** [ADR-AUDIO-017](../decisions/ADR-AUDIO-017-held-listening-from-a-button.md); workspace assignment `2026-11-20-va-hold-to-talk`.
**Overall status:** pending
**Why now:** the Flic Duo on glass-native talks through `hold` and `release`; silence must not end a held utterance.
**Time budget:** 15 minutes.
**What we are testing:** the commands reach voice-agent, a held utterance survives a pause, the release sends it, and the mode returns.

Status legend: as in [p040-agenda-notifications.md](p040-agenda-notifications.md).

| Case | Status |
|---|---|
| S1 Builds on the Pixel | pending |
| T1 Hold from Standby, pause inside, release | pending |
| T2 Hold in Listening | pending |
| T3 Listening during a hold | pending |
| T4 A release that never comes | pending |
| T5 Older glass-native | pending |

## Setup

- **S1** voice-agent of this branch installed on the Pixel, then glass-native of a debug build (its `DebugVaCommandReceiver` sends a command as the button does). **Status:** pending

## Test cases

### T1 Hold from Standby, pause inside, release

**Status:** pending

**Do:**
1. voice-agent in Standby.
2. `adb shell am broadcast -n casa.jarco.glassnative/.DebugVaCommandReceiver --es command hold`
3. Say a sentence, keep silent for 3 s, say a second one.
4. `… --es command release`

**Why:** decisions 2 and 3 of ADR-AUDIO-017.

**Expected:** logcat `GlassesControl … hold → accepted`, then `release → accepted`; one transcript holds both sentences; the mode goes Listening, then Standby.

**On failure:** two transcripts: the hold did not reach the engine (`hf.hold` missing in telemetry), look at `_startEngine` taking the hold after a resume.

### T2 Hold in Listening

**Status:** pending

**Do:** as T1 from Listening.

**Expected:** one transcript; the mode stays Listening.

### T3 Listening during a hold

**Status:** pending

**Do:** from Standby send `hold`, say a sentence, send `listening`, keep silent 2 s.

**Why:** decision 4.

**Expected:** the sentence goes out after the silence (VAD again); the mode stays Listening.

### T4 A release that never comes

**Status:** pending

**Do:** send `hold`, then nothing for 5 minutes.

**Why:** decision 5.

**Expected:** the utterance goes out after 5 minutes; the mode returns to where it was.

### T5 Older glass-native

**Status:** pending

**Do:** with glass-native v1 (main before the button tasks), use the page Rozmowa.

**Expected:** Włącz and Pauza work as before.

## When this plan is done

T1–T3 are must-pass. T4 and T5 may be skipped with a note.
