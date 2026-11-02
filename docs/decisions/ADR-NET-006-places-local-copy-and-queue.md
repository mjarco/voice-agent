# ADR-NET-006: Places are written on the phone first and sent while the app is in use

Status: Accepted

## Context

A place is named standing in it, often deep in a store with a poor link, and the
list must show it at once (workspace roadmap `2026-11-places`, goal 1). The same
place can be corrected in the web UI. personal-agent's ADR-API-112 gives a
phone-made id, a repeatable `PUT` and a newest-change-wins rule.

## Decision

1. **The phone keeps a copy.** Places, the queue and the store types live as one
   JSON value in `shared_preferences`. There are tens of places, nothing searches
   them, and this leaves the transcript database and its migrations alone.
2. **One owner.** `PlacesNotifier` is the only writer. Every change lands in the
   copy first, then goes out, and a send runs one at a time.
3. **Foreground only, as ADR-NET-002 says.** A send runs at app start, on a return
   to the app, when the link comes back, and on each change. There is no
   background path, so ADR-NET-002 stands unchanged.
4. **A refused place stays.** PA's refusal keeps the place on the phone, marked
   as waiting, says so on the screen and does not stop the others. A place is
   never dropped for lack of an answer.
5. **The reading is its own.** The Places screen asks Kotlin for one fresh position
   on `com.voiceagent/place_reading`, with the while-in-use permission. A place
   can be named with the location log off, and this reading is not a row of the log.

## Consequences

- A place saved with the app then left closed waits for the next opening.
- An unreadable copy is rebuilt from PA; only what was still waiting is lost.
- The web UI's delete has no tombstone: a place edited offline comes back, and
  the owner deletes it again (ADR-API-112).
- Goal 2 of the roadmap needs Kotlin to read places for geofences; it will add
  its own path to this data, and this ADR does not settle it.
