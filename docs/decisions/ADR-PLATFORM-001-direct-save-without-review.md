# ADR-PLATFORM-001: Direct save without review screen

Status: Accepted
Proposed in: P014

## Context

P003 introduced a transcript review screen (`/record/review`) where users could edit the transcript before saving. P014 overhauled the recording UX and re-evaluated whether the review step was necessary.

With hands-free mode producing multiple segments automatically, requiring manual review of each segment would break the flow. Manual recordings (tap-to-record, press-and-hold) are typically short voice notes where editing is rarely needed.

## Decision

Remove the review screen entirely. Both manual and hands-free recordings save and enqueue for sync directly without user review. The `RecordingCompleted` state is removed from the manual recording state machine.

Auto-start hands-free mode on `/record` navigation — the app enters listening mode immediately.

## Rationale

The review screen was designed for a single-recording workflow. With hands-free producing many short segments, requiring review of each would be impractical. For manual recordings, the overhead of a review step outweighs its value for short voice notes. Users who need to review can check transcript history.

## Consequences

- `/record/review` route removed — simplifies navigation.
- Transcripts are saved as-is from STT output — no user editing before save.
- Hands-free starts automatically when navigating to the record tab.
- `silentOnEmpty` parameter on `stopAndTranscribe()` handles empty press-and-hold gracefully (return to idle, no error).
- Three gesture types on mic button: tap (tap-to-record), long press (press-and-hold), auto (hands-free).
