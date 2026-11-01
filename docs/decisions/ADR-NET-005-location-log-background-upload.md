# ADR-NET-005: The location log uploads in the background

Status: Accepted

## Context

ADR-NET-002 keeps sync to the foreground, an active hands-free session and a few
narrow exceptions, and asks that a fourth use consider restructuring it rather
than adding a carve-out. The owner decided that location readings go to
personal-agent live, as each arrives, and are written locally when it cannot be
reached (workspace off-roadmap task `2026-11-01-location-log`). That cannot hold
under the foreground rule: most readings arrive with the app closed.

## Decision

Location rows, and nothing else, may be sent while the app is in the background:

1. Each new reading gets one direct `POST /location/entries` attempt, from the
   receiver or the service that wrote it.
2. What that attempt leaves goes to a unique WorkManager job, `location-log-drain`,
   with a network constraint and exponential backoff. It uses `androidx.work`
   directly, in Kotlin, not the `workmanager` plugin.
3. A send is repeatable: every row has a client-made id, and the server keeps the
   first. Rows refused for good leave the queue, with a status row saying so.
4. Rows leave the queue only on a reply that accounts for all of them, and
   redirects are not followed, so a 200 from something else empties nothing.
5. Writes and sends run on separate threads, so a hung server never holds a
   reading in memory unwritten.

`SyncWorker`, the transcript queue and the transcript contract are not affected:
this path posts one route, from its own store. The restructuring ADR-NET-002 asks
for is deferred, because this path shares no code with sync; it is recorded here
as a separate decision so that ADR-NET-002's rule stays readable.

## Consequences

- The log is switched on by the owner, and only then does traffic flow.
- In Doze and in low standby buckets a send may wait; `received_at` minus
  `recorded_at` measures it, which is one of the things the log is for.
- This grants no other feature a background path.
