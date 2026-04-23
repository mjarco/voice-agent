# Proposal 030 — TTS Mixed-Language Support via SSML `<lang>` Tags

## Status: Draft (seed)

## Origin

Conversation 2026-04-22. Current TTS pronounces English technical terms
("API", "action item", "hangover") with a Polish accent, to the point of
being unintelligible. The decision: TTS must honour mixed-language content,
with English fragments spoken in English.

## Prerequisites

- 015-tts-response-playback — the current TTS rendering path
- 028-background-tts — background TTS behaviour and platform-specific
  foreground service wiring

Both are implemented.

**Cross-project pair:** personal-agent proposal P054
(`mixed-language-ssml.md`) emits the SSML tags. Without them, client-side
work is dormant. Without client-side honouring, tags render as raw text.

## Scope

- Risk: Medium — touches TTS engine selection and cross-platform SSML
  rendering, which differ by platform
- Layers: `core/tts/` (the domain port + adapter both live here per
  ADR-ARCH-006), `features/api_sync` (caller that already feeds message
  text to `TtsService.speak`), `features/recording/presentation`
  (HandsFreeController — VAD suspend/resume contract must be preserved)
- Expected PRs: 2 (splitter + wiring, then per-platform verification).
  A third "cloud TTS fallback" PR is a follow-up, not part of v1.

## Problem Statement

Polish-primary conversations routinely include English technical terms.
Today those terms are sent to an on-device TTS that applies Polish phonetics,
producing output that the user cannot understand. Backend proposal P054 will
wrap those fragments in `<lang xml:lang="en-US">...</lang>`; the client must
render those tags correctly on both iOS and Android.

## Are We Solving the Right Problem?

**Root cause:** `FlutterTtsService.speak()` in `lib/core/tts/flutter_tts_service.dart`
calls `_tts.setLanguage(lang)` exactly once per utterance, where `lang` is
a single resolved locale (e.g. `pl_PL` or `en-US`). The platform engine
(AVSpeechSynthesizer on iOS, Google/Samsung/Pico TTS on Android) then
applies that single language's phonetic model to the entire string — so
an English term inside a Polish sentence is read with Polish phonetics.
The problem is not the STT output, not the LLM output, and not the TTS
engine selection; it is that we are asking one voice, once, to speak a
string that is semantically in two languages.

**Alternatives dismissed:**

- *Correct STT input to turn perceived Polish back into English before
  sending to the backend.* Rejected. Distorts the user's actual input,
  which the backend records as canonical conversation history, and does
  not fix the TTS output problem: even a clean English token still reaches
  the TTS engine inside a Polish sentence and gets mispronounced. Backend
  proposal P054 rejects the same alternative for the same reason.
- *Always route replies through a cloud TTS (ElevenLabs / Azure) that
  understands SSML natively.* Rejected for v1. Per-request cost,
  non-trivial latency added to the hands-free flow, and a network
  dependency on what is currently a zero-cost on-device feature. Cloud
  TTS remains a follow-up for cases where the on-device engines cannot
  deliver acceptable quality.
- *Strip English fragments from the reply before TTS so they are simply
  not spoken.* Rejected. Loses information — "set the hangover to 800 ms"
  becomes "set the to 800 ms" — and degrades the reply from a voice
  assistant to a broken summary.

**Chosen approach — engine-aware split:**
Parse the `<lang>`-tagged reply client-side into an ordered queue of
`(text, language)` segments. For each segment, drive the existing
`flutter_tts` engine with the right `setLanguage(...)` (and on iOS, the
right `setVoice(...)`) before speaking that segment, then chain the next
segment on completion. This preserves the current engine, the current
audio session behaviour (`ambient` per ADR-AUDIO-007, `playAndRecord`
during sessions per ADR-AUDIO-009), the current VAD suspend/resume
contract, and the zero-cost on-device model — while giving English
fragments an English voice.

**Smallest change?** Yes — a pure-Dart splitter plus a per-segment
queuing wrapper inside `FlutterTtsService`. No new engine, no new
permission, no new platform channel. Tagged replies from P054 render
correctly; untagged replies follow the existing single-segment path.

## Goals

- A reply containing `<lang xml:lang="en-US">API</lang>` is spoken with
  English phonetics on both iOS and Android release builds.
- No literal SSML tag audio reaches the user on any platform or any
  engine — tags are always stripped before they reach a speech synth.
- Untagged replies sound identical to the current 015/028 behaviour.
- The VAD suspend/resume contract from 028 is preserved — TTS still
  signals `ttsPlayingProvider` so `HandsFreeController.suspendForTts()`
  and `resumeAfterTts()` fire at utterance boundaries.

## Non-goals

- **No arbitrary language pairs.** v1 covers PL + EN only. If a reply
  contains `<lang xml:lang="de-DE">`, the segment is handled as a
  best-effort on whatever voice the platform picks for `de-DE`; we do
  not ship or configure German voices.
- **No voice customization beyond default PL/EN voices.** iOS picks the
  best available system voice per language (same premium/enhanced/normal
  selection `_bestVoice()` already does for the single-language case);
  Android uses `setLanguage()` with whatever engine the user has
  installed. No settings UI for picking voices.
- **No cloud TTS integration in v1.** Cloud fallback is explicitly
  deferred (see Known Compromises and the T4 follow-up task).
- **No streaming SSML from a partial reply.** The reply comes from
  `SyncWorker._handleReply` as a complete string; we do not need to
  parse partial `<lang>` tags arriving mid-stream.
- **No changes to backend SSML shape.** The shape is defined by P054
  and we consume it; we do not negotiate or propose alternatives here.

## User-Visible Changes

- With a P054-enabled backend: a reply like
  `Ustawiłem <lang xml:lang="en-US">hangover</lang> na 800 ms.` is
  heard as a Polish sentence with an English "hangover" in the middle,
  rather than Polish phonetics applied to "hangover".
- Without a P054-enabled backend: zero change — untagged replies play
  via the existing single-segment path.
- No new UI, no new setting, no new permission. The existing Settings
  toggle "Read API response aloud" still gates all TTS output.
- Brief pauses (tens to low-hundreds of ms) appear at language
  boundaries where one utterance stops and the next begins. Acceptable
  for v1 — better than mispronunciation.

## Solution Design

### SSML splitter (pure Dart, new file in `core/tts/`)

New class `SsmlLangSplitter` in `lib/core/tts/ssml_lang_splitter.dart`.
Input: the raw reply string (possibly containing `<lang xml:lang="…">…</lang>`).
Output: an ordered `List<TtsSegment>` where each segment has `text` (tag-free)
and `languageCode` (nullable — `null` means "use the default language this
reply was invoked with", i.e. fall through to the existing
`_resolveLanguage` path).

Parser contract:

- Walk the input left-to-right. Outside any tag, accumulate text as a
  default-language segment. On encountering a well-formed
  `<lang xml:lang="xx-YY">…</lang>` matching the P054 canonical shape
  exactly, close the current default segment (if non-empty) and emit
  one tagged segment with `languageCode = "xx-YY"` and `text = <inner>`.
- **Case-sensitive matcher — canonical shape only.** The matcher
  requires the exact lowercase element name `lang`, exact lowercase
  attribute name `xml:lang`, double-quoted value, and BCP-47 value
  formatted as `xx-YY` (lowercase primary, uppercase region). This
  matches P054's lowercase-only emission contract byte-for-byte. Any
  other casing (`<LANG>`, `<Lang xml:lang="EN-US">`, single-quoted
  attribute, missing attribute, extra attributes before `xml:lang`) is
  treated as **malformed** and falls through to the plain-text pathway
  — the tag characters are preserved in the default-language segment
  and pronounced literally. This surfaces any backend drift audibly
  (loud, ugly, visible in logs) instead of silently failing over to
  Polish phonetics on an unrecognised tag.
- **Value passed through unchanged** to `_tts.setLanguage(value)` and
  `_bestVoice(value)`. Both platforms accept the canonical `xx-YY` form
  directly: iOS `AVSpeechSynthesisVoice.speechVoices()` returns
  language codes in `xx-YY` form; Android `Locale.forLanguageTag`
  accepts it natively. No client-side normalization is performed or
  needed — if the value diverges from `xx-YY`, it failed the canonical
  matcher above and the segment is plain text.
- Nested `<lang>` is not supported in v1. On encountering a nested
  open-tag while inside an outer `<lang>` region, the splitter adopts
  rule (a): **inner wins, outer text around it emits as outer-language
  segments**. Example:
  `<lang xml:lang="en-US">Check the <lang xml:lang="pl-PL">polityka</lang> API</lang>`
  produces three tagged segments: `[(en-US, "Check the "), (pl-PL,
  "polityka"), (en-US, " API")]`. A log line records the nesting.
  Backend P054 does not emit nested tags today; this rule is defensive.
- **Malformed tags are emitted as plain text** (tag characters included
  literally — we do not strip them silently, because that would hide
  backend bugs; a visible-in-logs tag is louder than a pronounced one).
  Cases: missing closing tag, missing or misspelled `xml:lang`
  attribute, unmatched `</lang>`, wrong casing, single-quoted attribute,
  any other parse failure. The splitter must never throw — on any
  unexpected input it falls back to a single default-language segment
  carrying the original string.
- If the input begins with a `<speak>...</speak>` SSML envelope (P054
  does not emit one today, but future revisions might), the outer
  envelope is stripped before segmentation; content inside is parsed
  normally. Low-cost defensive parse — keeps the contract
  forward-compatible.
- Whitespace between segments is preserved as part of the adjacent
  default-language segment — we do not "trim" across tag boundaries.
  Trailing/leading empty default-language segments are elided.
- **Empty input** (`text == ""` or whitespace-only): splitter returns
  zero segments. `FlutterTtsService.speak()` early-returns in this case
  without touching `_tts`; `_speaking` stays `false`,
  `ttsPlayingProvider` never fires. No native speak call, no listener
  churn. Callers (`_handleReply`) are unaffected — `onAgentReply` still
  fires with the original (empty) message.
- No regex-only parser. Use a hand-rolled state machine so nested or
  adjacent tags don't catastrophically misparse. The logic is small
  (~40 lines) and fully unit-testable.

This is a pure Dart class with zero platform dependencies — easy to
unit test with high coverage and zero flakiness.

### Integration point: `FlutterTtsService.speak()`

Currently `FlutterTtsService.speak(text, languageCode: …)` does:

1. Resolve language.
2. `_tts.setLanguage(lang)` (and on iOS `_tts.setVoice(voice)` if a
   better one exists).
3. `_tts.speak(text)` — a single call, returns before playback finishes,
   fires `_tts.setCompletionHandler` on end.

Change: at the top of `speak()`, run the text through
`SsmlLangSplitter.split(text)`:

- If the result is a single segment with no explicit language override,
  follow exactly the current path — zero behaviour change for untagged
  replies.
- Otherwise, enter a per-segment queuing loop (see below).

### Per-segment queuing loop

A `speak()` call with N segments becomes N sequential `_tts.speak(...)`
calls, chained on the completion/error handlers. The queuing loop is the
**enclosing guard** that keeps `_speaking.value` high for the entire
logical utterance — the single invariant VAD depends on.

**State on the service instance:**
- `_SegmentQueue? _activeQueue` — nullable. Holds: remaining segments,
  resolved default language, a monotonically-increasing `int generation`
  (bumped every time a new queue starts), and a
  `Completer<void> doneCompleter` that fires when the last segment ends
  or when `stop()`/`dispose()` cancels.
- `bool _queueEntered` — internal flag set `true` on first
  `_tts.speak(segment[0])` of a queue, reset to `false` only when the
  queue drains or is cleared.

**Handler wiring (explicit):**
- `setStartHandler`: on fire, if `_speaking.value == false`, set it to
  `true`. On subsequent segments within the same queue, `_speaking` is
  already `true`, so this is a no-op (gated assignment — never flaps).
  No `ref.invalidateSelf()`-type re-notification fires on same-value
  assignments because `ValueNotifier` only notifies on actual value
  change.
- `setCompletionHandler`: on fire, inspect `_activeQueue`. If non-null
  AND has remaining segments, call `_advanceQueue()` — this advances the
  pointer, sets per-segment language/voice, calls `_tts.speak(next)`.
  **`_speaking.value` is NOT touched.** If `_activeQueue` is null OR the
  queue has drained, clear `_activeQueue`, set `_speaking.value = false`,
  complete `doneCompleter` (if not already completed).
- `setCancelHandler`, `setErrorHandler`: clear `_activeQueue` FIRST (so
  no racing completion advances), THEN set `_speaking.value = false`,
  then complete `doneCompleter` with the cancellation/error.

**Enclosing guard (try/finally around segment loop):**

```
Future<void> _runQueue(_SegmentQueue q) async {
  _activeQueue = q;
  _queueEntered = true;
  try {
    // First segment kicks off via _tts.speak; subsequent segments are
    // advanced by setCompletionHandler. This method returns when
    // doneCompleter completes.
    await _tts.speak(q.segments.first.text);
    await q.doneCompleter.future;
  } finally {
    // Invariant: when this method returns, _speaking is false exactly once
    // per logical utterance. The guard runs even on throw or cancellation.
    _activeQueue = null;
    _queueEntered = false;
    if (_speaking.value) _speaking.value = false;
  }
}
```

The try/finally is the enforcement point: no matter how the queue exits
(completion, error, cancel, stop, dispose), `_speaking` transitions
`true → false` exactly once, at the end.

**`_speaking` invariant summary:**
- false → true: exactly once, on first segment's `setStartHandler` fire.
- true → false: exactly once, on queue completion or explicit cancel.
- Between segments: stable at `true` — no flap, no transient `false`.
- Downstream: `ttsPlayingProvider` fires exactly `[false→true, true→false]`
  per logical utterance. `HandsFreeController.suspendForTts()` and
  `resumeAfterTts()` each fire exactly once per reply.

**`stop()` / `speak()` race ordering:**

`SyncWorker._handleReply` (`sync_worker.dart:196`) calls
`ttsService.stop().then((_) => ttsService.speak(message, …))`. With
per-segment queuing, a stale completion handler from the previous
queue's native-side `_tts.stop()` could fire after a new queue starts
and mistakenly advance it, causing the first segment of the new reply to
be skipped. Ordering to prevent this:

1. `stop()` is `async`. It first sets `_activeQueue = null` (so any
   stale completion sees null and exits early), then `await _tts.stop()`
   (waits for the native-side cancel to complete), then completes any
   pending `doneCompleter` with a cancellation marker. `stop()` returns
   only after the native stop has been acknowledged.
2. `speak()` bumps a `_queueGeneration` counter, builds a new
   `_SegmentQueue` with that generation stamped in, sets it as
   `_activeQueue`, and enters `_runQueue`.
3. Every handler closure captures the generation at registration time
   (in the queue struct) and on fire checks `_activeQueue?.generation ==
   captured_generation`. A stale handler from generation N firing after
   generation N+1 has started sees a mismatch and returns immediately,
   without touching `_speaking` or advancing.

This guarantees: back-to-back `stop().then(speak)` produces two
independent queues; no cross-talk; segment 1 of the new queue is never
dropped. A unit test (`test stop→speak does not swallow segment 1`)
pins this behaviour.

- Per-segment language is applied by calling `_tts.setLanguage(seg.lang)`
  (and on iOS `setVoice(bestVoiceFor(seg.lang))`) before each
  `_tts.speak(seg.text)`. The existing `_voiceCache` already benefits
  multi-segment replies since the same `lang` repeats across replies.
- Segments with `languageCode == null` resolve via the current
  `_resolveLanguage` path using the `speak()` call's own `languageCode`
  argument — so the default-language behaviour of an untagged reply is
  preserved.

### iOS path

`flutter_tts` on iOS wraps `AVSpeechSynthesizer`. `AVSpeechSynthesizer`
does not natively parse SSML `<lang>` — it takes an `AVSpeechUtterance`
whose `.voice` property drives the phonetic model. `flutter_tts` does
expose `setLanguage(...)` and `setVoice(Map<String,String>)` methods
that set the next utterance's voice. Confirmed in the existing
`_bestVoice()` lookup: we already call `setVoice()` per-call. **No
bridge or platform channel needed** — we just call `setVoice` before
each segment's `speak`. T1 will add a device smoke that verifies each
segment uses its intended voice on a real iPhone.

If a device does not have the required English voice installed (some
region-locked devices), `AVSpeechSynthesizer` falls back to the system
default and we still ship the reply without tag audio — degraded, not
broken. Logged at info level.

### Android path

Android TTS engine behaviour for `<lang>` is engine-specific, and we
deliberately do **not** probe engines in v1.

- **Google TTS** (default on most Android 10+ devices): per public
  documentation, Google TTS does not reliably parse SSML through
  the `flutter_tts` plugin API. The plugin passes strings to
  `TextToSpeech.speak()`, which treats SSML-like input as literal
  text unless wrapped in an `<speak>` envelope and flagged — and the
  plugin does not expose the SSML flag.
- **Other engines** (Samsung, Pico, AOSP, etc.): variability in SSML
  handling is why we do not attempt pass-through.

**V1 decision: apply the splitter path uniformly on Android, regardless
of engine.** This keeps the path deterministic, testable, and identical
to iOS. `setLanguage(Locale)` is called per segment before each
`_tts.speak()`. Since the splitter always strips tags when producing
segments, no engine ever receives tag characters — no risk of a
literally-spoken `<lang>`.

**Engine capability probing is explicitly deferred, not impossible.**
`flutter_tts` 4.x exposes `getEngines`, `setEngine`,
`isLanguageInstalled`, and `getDefaultEngine` — a future proposal
could probe the engine at splitter entry and short-circuit to a single
`speak(raw_ssml)` call on engines known to handle SSML natively, reducing
the inter-segment gap. We do not do this in v1 because (a) no engine has
documented SSML `<lang>` support through `flutter_tts`'s current API
surface, (b) engine variability across Samsung/Google/Pico/AOSP means a
probe must be tested per device class, and (c) the v1 splitter path is
the correctness baseline — a capability probe would be a latency
optimisation, not a correctness fix. **Follow-up candidate:** if
real-world inter-segment gap measurement on Android exceeds the
tolerance threshold (see T3 smoke), a probe-based fast path is a
natural next proposal alongside T4 (cloud TTS).

### Fallback (deferred follow-up)

Cloud TTS (ElevenLabs / Azure) would accept the full SSML string
unchanged and return a single audio buffer we could play via
`audioplayers` or a lightweight native bridge. This is scoped as T4
in the Tasks table and **is not part of v1**. v1 ships the splitter
path on both platforms and observes real-world quality. If a
follow-up proposal decides the on-device output is insufficient,
that proposal takes the decision to add a cloud dependency with
explicit cost and latency budgets.

### Tag stripping — safety net

Two defensive behaviours must hold even on unexpected input:

1. No platform `speak()` call ever receives a string containing `<lang`
   or `</lang>`. Enforced by the splitter: every emitted segment's
   `text` field is tag-free.
2. For malformed input that the splitter declines to parse (see above),
   the whole reply is passed to a single default-language `speak()`
   call with the literal text — *not* silently dropped. The user hears
   the tags as characters, which is ugly, but the fix is in P054
   (backend), not in swallowing errors here.

### VAD suspend/resume contract (preserved)

- `ttsPlayingProvider` flips to true when the first segment begins and
  back to false only after the last segment completes (see per-segment
  queuing loop, above). This matches the 028 contract exactly.
- `HandsFreeController.suspendForTts()` is called once per reply, not
  per segment — VAD stays paused across the whole reply, no mid-reply
  re-arming.
- `HandsFreeController.resumeAfterTts()` fires once, on queue
  completion or explicit `stop()`.
- `EngineCapturing` (user started speaking) still calls
  `ttsService.stop()` from `HandsFreeController._onEngineEvent` — that
  path now clears the in-flight queue cleanly.

## Affected Mutation Points

**New files:**

- `lib/core/tts/ssml_lang_splitter.dart` — pure-Dart splitter class
  and `TtsSegment` model. No platform imports.

**Needs change:**

- `lib/core/tts/flutter_tts_service.dart` (`FlutterTtsService.speak`,
  `stop`, `dispose`, handler wiring, internal queue state):
  - Add `_SegmentQueue? _activeQueue` field carrying segments,
    resolved default language, a `Completer<void> doneCompleter`, and
    a monotonic `int generation` stamp.
  - Add `int _queueGeneration` counter; bump on every new `speak()`
    invocation.
  - Rewrite `speak()` to run text through `SsmlLangSplitter.split()`
    and, for N≥1 segments, drive a per-segment loop inside a
    try/finally enclosing guard (see §Per-segment queuing loop) that
    holds `_speaking.value = true` across the whole queue and flips it
    `false` exactly once on queue exit.
  - Adjust the existing `setStartHandler` to gate
    `_speaking.value = true` on "only if currently false" (idempotent,
    no listener flap between segments). Adjust
    `setCompletionHandler` to advance the queue when
    `_activeQueue != null` and has remaining segments, only flipping
    `_speaking.value = false` when the queue is drained or cleared.
    Adjust `setCancelHandler` / `setErrorHandler` to clear
    `_activeQueue` BEFORE setting `_speaking.value = false` and
    completing `doneCompleter`.
  - Every handler closure captures its queue's `generation` at
    registration. On fire, the handler checks
    `_activeQueue?.generation == captured_generation` — if not, it is
    stale (superseded by a newer `speak()`) and returns immediately
    without touching state or advancing.
  - Rewrite `stop()` to: (1) set `_activeQueue = null` so any racing
    completion sees null, (2) `await _tts.stop()` so the native side
    finishes before the caller's `.then(speak)` runs, (3) complete
    any pending `doneCompleter` with a cancellation marker, (4)
    ensure `_speaking.value = false`. `stop()` returns only after all
    four steps.
  - Rewrite `dispose()` to clear `_activeQueue`, complete any pending
    `doneCompleter` with a cancellation error, then `_tts.stop()` and
    dispose `_speaking`. Prevents leaked Completers on hot-reload.
  - Keep the iOS `_bestVoice()` cache logic unchanged — it works
    per-language and benefits the multi-segment case. First tagged
    reply of a new language incurs one-time `getVoices` lookup
    (≤10ms on iOS); subsequent replies hit the cache.

**No change needed:**

- `lib/core/tts/tts_service.dart` — the `TtsService` port already
  takes `speak(String text, {String? languageCode})`; multi-segment
  rendering is an implementation detail.
- `lib/core/tts/tts_provider.dart` — no provider shape change.
- `lib/features/api_sync/sync_worker.dart` (`SyncWorker._handleReply`) —
  still calls `ttsService.stop().then((_) => ttsService.speak(message,
  languageCode: language))`. The tagged message flows through unchanged.
  The `stop→speak` race (stale completion handler from the previous
  queue's native-side stop firing after a new queue starts) is handled
  entirely inside `FlutterTtsService` via the generation counter plus
  `stop()` awaiting `_tts.stop()` (see §Per-segment queuing loop).
  `_handleReply` needs no change.
- `lib/features/recording/presentation/hands_free_controller.dart`
  (`HandsFreeController._onEngineEvent`, `suspendForTts`,
  `resumeAfterTts`) — the suspend/resume contract is driven by
  `ttsPlayingProvider`, which keys off `_speaking` now held `true`
  across the queue.
- `AndroidManifest.xml`, iOS `Info.plist`, background service
  registration — unchanged from 028.

## Test Impact / Verification

### Unit tests (new)

`test/core/tts/ssml_lang_splitter_test.dart`:

- Empty input → zero segments (consistent with the splitter contract;
  `speak()` early-returns without touching `_tts`).
- Untagged text → one default segment with exact input text.
- Single `<lang xml:lang="en-US">X</lang>` → three segments: leading
  default, tagged en-US, trailing default (empty segments elided).
- Multiple adjacent `<lang>` regions with different language tags.
- Unclosed `<lang>` tag → full string returned as one default segment
  (fallback path); must not throw.
- Unmatched `</lang>` → same fallback.
- Nested `<lang>` → inner wins, outer is logged; must not throw.
- Mixed-case attribute `XML:LANG` or `<Lang>` element → treated as
  malformed (case-sensitive matcher), emitted as plain text in the
  default-language segment. Test asserts the tag characters appear
  verbatim in the resulting segment.
- Whitespace and punctuation adjacent to tags preserved.

`test/core/tts/flutter_tts_service_test.dart` (extended):

- Injected `MockFlutterTts` records `setLanguage`, `setVoice`, `speak`
  calls in order. A two-segment input produces: `setLanguage('pl_PL')`,
  `speak('…')`, (completion), `setLanguage('en-US')`, `speak('…')`.
- `_speaking` (via `isSpeaking` listener) stays `true` between segment
  1 completion and segment 2 start — not flapping.
- `stop()` called mid-queue prevents segment 2 from being spoken.
- Untagged input produces exactly one `setLanguage` and one `speak`
  (no regression vs current behaviour).
- **AC4 coverage — `ttsPlayingProvider` transition counter.** Pump a
  two-segment speak through `FlutterTtsService` inside a
  `ProviderContainer`. Attach a listener to `ttsPlayingProvider` that
  appends each (prev, next) state pair to a list. Assert the list is
  exactly `[(false, true), (true, false)]` — one pair, not two pairs.
  This counts state transitions (not just the final value) and fails
  if the handler wiring ever flaps `_speaking` mid-queue. This is the
  direct test of AC4 ("`ttsPlayingProvider` transitions exactly once
  per utterance").
- **`stop→speak` race.** Call `ttsService.stop()` immediately followed
  (in the `.then` continuation) by `ttsService.speak(twoSegmentInput)`.
  Fire a stale completion event from the mock _after_ the new queue's
  first segment starts. Assert: (a) the new queue's segment 1 is not
  skipped, (b) the new queue's segment 2 is spoken after segment 1
  completion, (c) `_speaking` follows `[false→true, true→false]`
  exactly once across the new queue (not twice).
- **Generation counter.** Start queue A (gen=1), call `stop()`, start
  queue B (gen=2). Fire a completion handler captured against gen=1
  after queue B has started; assert queue B's state is unchanged (no
  accidental advance, no `_speaking` flip).

### Existing tests — impact

- `test/features/api_sync/sync_worker_test.dart` — no impact; it stubs
  `TtsService` and verifies `.speak()` is called with the raw message.
  The splitter is an implementation detail.
- `test/features/recording/presentation/hands_free_controller_test.dart`
  — no impact; still asserts `stop()` is called on `EngineCapturing`.
- Widget tests that pump `RecordingScreen` / `SettingsScreen` with a
  stub `TtsService` — no impact.

### Device smoke (required before marking Implemented)

1. **iOS (iPhone 12 Pro, release build), PL voice + EN voice installed.**
   Trigger a P054-shaped reply. Expected: Polish sentence with an
   English "hangover"/"action item" in the middle, unambiguously
   English phonetics. No tag characters audible. No mid-reply VAD
   re-arm. Lock screen during the reply — audible (028 behaviour).
2. **Android 14+ (Pixel or similar, release build), Google TTS, PL + EN
   language packs installed.** Same smoke as iOS.
3. **Android 13 / pre-Android-14 device (if available).** Same smoke —
   confirms the splitter path also works on the non-typed-FG-service
   Android generation from 028.
4. **iOS without EN voice installed.** Trigger tagged reply. Expected:
   reply still plays, English fragment falls back to device default
   voice, log line present; no crash, no tag audio.
5. **Malformed backend input** (manual: send a handcrafted reply with
   an unclosed tag via backend stub). Expected: user hears the raw
   text including `<` characters; no crash; logs show the parse
   failure.

**Commands:** `make verify` (runs `flutter analyze && flutter test`).

## Risks

| Risk | Mitigation |
|------|------------|
| Per-segment queuing introduces audible gaps at language boundaries that feel sluggish | Accepted for v1 — better than mispronunciation. Measure real-world gap on device; if intolerable, T4 (cloud TTS) becomes the fallback. The gap is bounded by `AVSpeechSynthesizer` / Android TTS handler latency, typically tens of ms. |
| iOS device lacks the required English voice pack (region-locked, storage-constrained) | `_bestVoice(en-US)` returns null → `setVoice()` skipped → `AVSpeechSynthesizer` falls back to default for the BCP-47 tag. Logged at info level. Degraded, not broken. |
| Android engine variability (Samsung/Pico/AOSP) — `setLanguage(Locale("en","US"))` returns `LANG_NOT_SUPPORTED` | Log and fall through to default; the segment is still spoken (with default phonetics), no crash. A future proposal could surface a user warning. |
| Malformed SSML from backend (unclosed `<lang>`, bad BCP-47 tag, nested tags) | Splitter returns a fallback single default-language segment; the full raw string is spoken including tag characters. Loud, ugly, but visible — better than silent drops. Unit-tested. |
| Race: `stop()` called while segment N is still in `flutter_tts`'s native queue, segment N+1 starts after stop | `stop()` clears `_activeQueue` before calling `_tts.stop()`. Completion handler checks `_activeQueue != null` before advancing — if null, no next segment is scheduled. Unit-tested. |
| `_speaking.value` held `true` across segments breaks an existing consumer that assumed per-utterance flapping | Only consumer is `ttsPlayingProvider` → `HandsFreeController.suspendForTts/resumeAfterTts`. This is the desired behaviour (VAD stays paused across the whole reply). Reviewed. |
| VAD re-arms between segments if `_speaking.value` ever flips false mid-queue | Covered by explicit unit test: two-segment speak holds `isSpeaking == true` continuously from start of seg1 to end of segN. |
| SSML tag reaches engine and is spoken literally | Splitter is the single source of truth; every emitted `TtsSegment.text` is asserted tag-free in unit tests. |

## Alternatives Considered

- **STT-side correction** — already dismissed in "Are We Solving the
  Right Problem?" above. Distorts user input, doesn't fix TTS.
- **Cloud TTS always-on** — v1 over-scope; deferred to T4 follow-up.
  See Known Compromises.
- **Strip English terms entirely** — loses information; reply becomes a
  broken summary. Dismissed.
- **Ask Android's Google TTS to parse `<speak>…<lang/>…</speak>`
  SSML natively.** Investigated; `flutter_tts` does not expose the
  bundle flags needed to flag input as SSML, and Google TTS's SSML
  support for non-English voices is underdocumented. Even if it
  worked, we'd still need the splitter path on iOS, so a uniform
  splitter path on both platforms is simpler and more testable.
- **Introduce a new TTS port with multi-segment API**
  (`Future<void> speakQueue(List<TtsSegment>)`) and migrate callers.
  Rejected — the only caller is `SyncWorker._handleReply`, which has
  a single string. Keeping `speak(String)` as the port and hiding
  multi-segment queuing inside the adapter preserves the current
  contract and avoids port churn.
- **Parse SSML with `xml` package.** Rejected — full XML parsing is
  overkill for one tag, adds a dependency, and is slower than the
  hand-rolled state machine on the happy path. Correctness for our
  single supported tag is easy to cover with unit tests.

## Known Compromises and Follow-Up Direction

- **Cloud TTS fallback deferred.** We ship v1 with splitter-driven
  on-device playback on both platforms. If real-world quality on the
  available device matrix is insufficient — in particular if Android
  engines produce noticeably worse English phonetics than iOS — a
  follow-up proposal (see T4) will prototype ElevenLabs or Azure and
  gate it on a "tagged reply detected" flag so cost is bounded.
- **Per-user voice selection deferred.** No Settings UI for picking
  specific iOS voices per language or forcing a particular Android
  engine. iOS uses `_bestVoice()` selection heuristics already in
  place; Android uses whatever engine the user's device came with.
  A follow-up proposal could add a "TTS voices" section to Settings.
- **PL + EN only in v1.** Other language pairs will *work* if the
  device has the voices installed, but we do not test, document, or
  support them as a feature.
- **Minor audible gap at language boundaries.** Bounded by platform
  handler latency; accepted as the cost of the splitter approach.
  Cloud TTS (T4) would eliminate it by producing a single audio buffer.

## ADR Impact

- **ADR-ARCH-006 (Domain port pattern).** The change respects the
  pattern: the port `TtsService` in `core/tts/` stays a thin
  abstraction; multi-segment queuing is implementation detail in
  `FlutterTtsService`, which already lives alongside the port. No
  ADR amendment needed.
- **ADR-AUDIO-007 (iOS ambient audio session for playback).** No
  change — we do not alter the audio session category. TTS continues
  to play via whatever category is active (`ambient` by default,
  `playAndRecord` during hands-free sessions per ADR-AUDIO-009).
- **ADR-AUDIO-009 (Conditional iOS audio session).** No change — the
  splitter runs entirely above the audio session layer.
- No new ADR proposed. The splitter is a localized implementation
  pattern, not a cross-cutting architectural decision. If a future
  proposal swaps in cloud TTS (T4), that proposal should decide
  whether a new ADR on "TTS engine selection" is warranted.

## Tasks

Each task is a mergeable PR with tests unless marked as a follow-up.

| # | Task | Layer | PR scope |
|---|------|-------|----------|
| T1 | Implement `SsmlLangSplitter` + `TtsSegment` model in `lib/core/tts/ssml_lang_splitter.dart`. Full unit test coverage (happy path, malformed input, mixed-case attributes, nested tags, whitespace). Pure Dart, no platform deps. | core/tts | PR 1 |
| T2 | Wire splitter into `FlutterTtsService.speak()` with per-segment queuing; preserve `_speaking.value = true` across the whole queue; make `stop()` drain the queue. Extend `flutter_tts_service_test.dart` to cover: two-segment happy path (ordered `setLanguage`/`speak` calls), `isSpeaking` held across segments, `stop()` mid-queue prevents subsequent segments, untagged input unchanged from current behaviour. | core/tts | PR 1 (same branch as T1 — splitter and caller land together) |
| T3 | Device smoke on iPhone 12 Pro + Android 14+ Pixel + one pre-Android-14 device; verify English fragment is audibly English, no tag audio, VAD does not re-arm mid-reply, lock-screen playback (028) still works. Record results in the proposal before marking Implemented. | manual | PR 2 — smoke-only doc update, no code diff |
| T4 | **(Follow-up, not v1.)** Prototype cloud TTS fallback (ElevenLabs or Azure) for tagged replies only: detect `<lang` in body, route that reply to cloud synth, fall back to v1 splitter path on network error. Gated by a new `cloudTtsEnabled` setting, default off. Requires a follow-up proposal with cost/latency budgets before implementation. | core/tts + features/settings | Separate follow-up proposal + PR |

## Acceptance Criteria

1. A reply containing `<lang xml:lang="en-US">API</lang>` (exact
   lowercase canonical shape) is spoken with English phonetics on both
   iOS and Android release builds.
2. No literal tag audio reaches the user on any platform, any engine —
   every emitted `TtsSegment.text` is tag-free.
3. Untagged replies sound identical to current 015/028 behaviour
   (one `setLanguage`, one `_tts.speak`, unchanged path).
4. **`ttsPlayingProvider` / `_speaking` transitions exactly once per
   logical utterance.** During a multi-segment reply, the provider
   emits exactly `[false→true, true→false]` — never flaps mid-queue.
   `HandsFreeController.suspendForTts()` and
   `resumeAfterTts()` each fire exactly once per reply, never
   per-segment. Enforced by the try/finally enclosing guard in
   `_runQueue()` and by gated `_speaking` assignments in the
   `setStartHandler`. Covered by the unit test counting
   `ttsPlayingProvider` state transitions (assert count == 1 pair per
   utterance).
5. Malformed SSML (wrong casing, missing attribute, unclosed tag,
   nested `<speak>` envelope, non-canonical shape) does not crash the
   app; the reply is spoken (tag characters included) and the parse
   deviation is logged at info level.
6. **Case-sensitive matcher.** The splitter matches only
   `<lang xml:lang="xx-YY">` canonical form (lowercase element,
   lowercase attribute, double-quoted BCP-47 `xx-YY` value). Any other
   casing is treated as malformed and falls through to plain text.
   Matches the P054 lowercase-only emission contract byte-for-byte.
7. **`stop→speak` race is safe.** Back-to-back
   `ttsService.stop().then((_) => ttsService.speak(newReply))` produces
   two independent queues with no cross-talk; segment 1 of the new
   reply is never dropped by a stale completion handler from the old
   queue. Covered by unit test.
8. `make verify` passes (`flutter analyze && flutter test`), and the
   architecture dependency rule is respected (splitter in `core/tts/`,
   no cross-feature imports).
9. Device smoke (T3) is recorded in this proposal before status flips
   to Implemented.

## Review Notes (2026-04-23)

Reviewed as Tier 2. Verdict: Ready with caveats. No P0/P1. P2 findings
accepted as implementation notes:

- **`_runQueue` pseudocode:** `await _tts.speak(...)` returns on platform
  acknowledgement, not playback end. `doneCompleter.future` is the actual
  "wait for all segments" signal. Implementer must not confuse the two.
- **Mock rework for T2 tests:** `_MockFlutterTts` must be extended to
  capture `setStartHandler`/`setCompletionHandler`/`setCancelHandler`/
  `setErrorHandler` registrations and expose methods to fire them on
  demand. This is a T2 prerequisite, not optional.
- **Empty input contract:** Committed to zero segments (fixed in test
  plan). `speak()` early-returns without touching `_tts`.
- **`speak()` completion semantics change:** With queuing, `speak()`
  returns after all segments complete (via `doneCompleter`), not after
  platform ack. No caller currently awaits it, so no functional impact.
  Documented as conscious change.
- **Per-language cache miss cost:** `_bestVoice()` incurs one platform
  channel call per new language per session. First tagged reply pays
  ~20ms (PL + EN). Acceptable for v1.

## Related

- personal-agent proposal P054 mixed-language-ssml (counterpart)
- 015-tts-response-playback
- 028-background-tts
- P000-backlog entry "TTS mixed-language support — honor SSML `<lang>` tags"
- ADR-ARCH-006 (domain port pattern), ADR-AUDIO-007 (iOS ambient),
  ADR-AUDIO-009 (conditional iOS audio session)
