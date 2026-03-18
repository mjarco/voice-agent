---
name: create-proposal
description: Use when starting work on any new feature or behavior change in the voice-agent project. Creates a properly formatted proposal document in docs/proposals/ before any implementation begins.
---

# Create Proposal

Every new feature or behavior change in voice-agent **must have a proposal document**
before any implementation starts. This skill guides creating one correctly.

**Core principle:** A proposal is the contract between intent and implementation.
Without it, review and GitHub issue creation have no baseline to work from.

**Announce at start:** "I'm using the create-proposal skill to document this feature."

---

## When to Use

**Mandatory — before any implementation:**
- New user-facing feature
- Change to existing feature behavior
- New API endpoint or change to existing one
- State machine change (new phase, new transition)
- New background worker or scheduler
- Configuration or startup behavior change

**Not needed for:**
- Bug fixes that don't change intended behavior
- Refactoring with no behavioral impact
- Test-only changes
- Documentation fixes

---

## Step 1: Determine Proposal Number

```bash
ls docs/proposals/ | grep -E '^[0-9]+' | sort | tail -1
```

Next number = last number + 1. Pad to 2 digits (e.g. `13`, `14`).

**Format:** `docs/proposals/{NN}-{short-kebab-name}.md`

---

## Step 2: Research Before Writing

Before writing, understand the problem area:
- Read existing code in the affected area
- Identify which architectural layers are touched (domain / application / infrastructure)
- Check related existing proposals in `docs/proposals/`
- Identify which tests will need updating

---

## Step 3: Write the Proposal

The proposal file **must contain all sections** below. Sections marked **(mandatory)**
cannot be omitted. Sections marked **(when applicable)** may be skipped with a
one-line justification (e.g. "No prerequisites — standalone feature").

### Section order and requirements

---

### Header Block (mandatory)

Placed immediately after the title and status. Gives the reviewer a 5-second
orientation before reading the body.

```markdown
# Proposal NN — Title

## Status: Draft

## Prerequisites
- P45c (Resource Invalidation Events) — must be merged
- `extraResourceEvents()` infrastructure operational

## Scope
- Tasks: ~3
- Layers: application, infrastructure, obsidian plugin
- Risk: Low — extends existing pattern
```

**Prerequisites:** Other proposals, infrastructure, or code that must exist
before this proposal can be implemented. "None" is a valid answer.

**Scope:** Quick size signal for the reviewer. Number of tasks (approximate),
architectural layers touched, and a one-phrase risk assessment (Low / Medium / High
with reason).

---

### 1. Problem Statement (mandatory)

Explain:
- What is the user experiencing today that is wrong or missing?
- Why does this matter to the user? What does it unlock or fix?
- Concrete example of the pain (e.g. "opening the dashboard shows yesterday's data")

Bad: "We need day reset logic."
Good: "When the user opens the Obsidian dashboard after midnight, they see stale
data from the previous day — plan items, focus state, and counters all reflect
yesterday. There is no way to start fresh without manually calling `dd morning`
twice or restarting the server."

---

### 2. Are We Solving the Right Problem? (mandatory)

This section forces an explicit check on problem framing before jumping to
solutions. Answer three questions:

1. **What is the root cause?** Trace the symptom back to its origin. Is the
   problem statement targeting the root cause, or a downstream effect?
2. **What alternatives were dismissed and why?** Even if the answer is obvious,
   write it down. Documenting "we could also X but chose not to because Y"
   prevents revisiting the same question during implementation.
3. **Is this the smallest change that solves the problem?** If a simpler
   approach exists (config change, one-line fix, reuse of existing mechanism),
   explain why it's insufficient — or adopt it instead.

Example (good):

```markdown
## Are We Solving the Right Problem?

**Root cause:** Conversation panels have no push notification when messages change.
They rely on 2-second polling (FocusCard, DayPlan) or have no async sync at all
(HandoffCard).

**Alternatives dismissed:**
- *Faster polling (500ms):* Reduces latency but wastes bandwidth and doesn't
  solve HandoffCard (which has no polling). Addresses symptom, not cause.
- *Include messages in /state response:* Would make /state a God endpoint.
  Components already know how to fetch their own data — they just need a trigger.

**Smallest change?** Adding a WebSocket event type is minimal — it reuses
existing P45c infrastructure (extraResourceEvents, onResource) and requires
no new endpoints or data models.
```

Example (bad — just restating the problem):

```markdown
## Are We Solving the Right Problem?

Yes, conversation panels need to update in real time. This proposal solves that.
```

---

### 3. Goals and Non-goals (mandatory)

**Goals** — 2-5 bullet points stating what the proposal achieves. These are
higher-level than acceptance criteria: they state *intent*, not *verification*.

**Non-goals** — explicit boundaries. What this proposal deliberately does NOT
do. Non-goals prevent scope creep during implementation and review.

Even for small proposals, write at least 2 goals and 2 non-goals.

---

### 4. User-Visible Changes (mandatory)

2-3 sentences describing what changes from the user's perspective. This grounds
the technical design in observable outcomes.

For backend-only changes with no UI impact: "No user-visible changes. This is
internal infrastructure for [purpose]." is a valid answer.

For UI changes: describe what the user sees before and after. ASCII mockups
(like P09) are welcome but not required.

---

### 5. Solution Design (mandatory)

Explain the technical approach:
- What mechanism solves the problem?
- Which features/layers will be modified?
- Key design decisions and trade-offs
- Constraints and invariants that must be preserved
- API contracts: endpoint signatures, event shapes, JSON structures (be precise)

**What belongs here:** Contracts, data flow descriptions, decision rationale,
state transition rules, interface signatures.

**What does NOT belong here:** Implementation code. Do not include Dart
snippets that look like ready-to-paste code. These age instantly and
mislead the implementer into treating the proposal as a spec. If a non-obvious
algorithm needs illustration, use pseudocode. Concrete implementation hints
belong in the task descriptions.

---

### 6. Affected Mutation Points (mandatory)

Before writing tasks, enumerate **all methods/functions that mutate the state
being changed**. This prevents partial fixes where some code paths get updated
but others are missed.

Keep this section as a **summary list** — just method names and whether they
need change. Do not embed full code snippets or detailed implementation notes
here (those go into tasks).

```markdown
## Affected Mutation Points

All methods that call SaveSession() or AppendMessage():

**Needs change:**
- `ConversationService.OpenSession()` — emit event on session creation
- `ConversationService.Send()` — emit on human msg and agent reply
- `AgentReviewExecutor.publishReviewResult()` — emit on result posted

**No change needed:**
- `ConversationService.Send()` line 165 (ThreadID update) — metadata-only, not user-visible
```

Rules:
- Use `grep` to find all callers of the relevant Save/Persist function
- Every mutation point must be listed, even if no change is needed
- If a mutation point needs change, it must be covered by a task
- Detailed per-site implementation notes go into the relevant task description, not here

**Why this matters:** P29 fixed CompleteFocus and DismissFocus but missed
PauseFocus and ResumeFocus — same state, same bug class, caught only in
production. This section would have surfaced the gap at review time.

---

### 7. Tasks (mandatory)

Tasks are the unit of execution. Each task becomes a GitHub issue and is
implemented as one branch + one PR.

**The granularity rule:** A task = one mergeable PR that leaves the system in
a consistent state.

Criteria for a well-scoped task:
- After merge: `flutter test` and `flutter analyze` pass, no broken behavior, no dead code waiting
  for a follow-up task to become useful
- Before merge: diff is reviewable in one pass (target <300 LOC net change)
- **Tests are always included in the same task as the code they test** — a test
  is never a separate task

**Format:** Use a table for scanability, with optional expansion below for
complex tasks.

```markdown
## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Backend: emit conversation events from ConversationService and AgentReviewExecutor, wire bus injection, add tests | application, infra |
| T2 | Frontend: wire onResource("conversations_changed") in HandoffCard, FocusCard, DayPlan; replace polling with event subscription | obsidian |

### T1 details

- Inject `EventBusPort` into `ConversationService`, update constructor and wiring in `app.go`
- Emit `LevelDay` with `conversation_id` at: OpenSession, Send (human + agent), CloseSession, EnsureStepSession (creation path)
- Emit from `AgentReviewExecutor.prepareAgentReview` and `publishReviewResult`
- Add `conversation_id` clause to `extraResourceEvents`
- Tests: `TestConversationService_BusEmissions`, extend `TestExtraResourceEvents` table
```

**Anti-patterns to avoid:**
- Micro-tasks that aren't independently mergeable (e.g. "add one if-clause" with
  no tests and nothing consuming the change)
- Mega-tasks that bundle 3+ unrelated concerns
- Separate test tasks — tests go with the code they verify
- Frontend + backend in one task when each side is non-trivial (>100 LOC each)

**Cross-check:** Every mutation point marked "needs change" must be covered by
a task. Every task must reference which mutation points it addresses.

---

### 8. Test Impact (mandatory)

Describe which existing tests change and which new tests are needed:

**Existing tests that change:**
- Which test files are affected and why
- Which assertions need updating

**New tests:**
- Unit tests: what new functions/methods need table-driven tests
- Integration tests: which new scenarios in `tests/e2e/`
- How to run: `flutter test`

If no E2E tests are needed, explain why.

---

### 9. Acceptance Criteria (mandatory)

Numbered list of verifiable outcomes. Each criterion must be testable:

```markdown
## Acceptance Criteria

1. On server startup, if `Day.Date` is before today, server logs "stale day detected"
   and resets `Day.Phase` to `not_started`.
2. `GET /state` after startup returns `Day.Phase = "not_started"` when previous day
   was stale, regardless of previous phase.
3. `GET /memory/today?date=2026-01-01` returns action records for that specific date.
4. `GET /memory/today?date=bad` returns HTTP 400.
5. `flutter test` and `flutter analyze` pass with no new issues.
```

---

### 10. Risks (when applicable — mandatory for Medium/High risk proposals)

Table format with mitigation:

```markdown
| Risk | Mitigation |
|------|------------|
| Thread growth in long review sessions | Desired behavior — thread is the audit trail |
| Schemaless persistence in Instance.Variables | Explicit V1 pragmatism; follow-up to promote to typed fields |
```

---

### 11. Alternatives Considered (when applicable — mandatory when introducing a new pattern)

For proposals that introduce a new architectural pattern, a new primitive, or
make a significant design choice: document at least 2 alternatives with
assessment of why they were rejected.

Not needed for proposals that extend an established pattern (e.g. "add a third
event type following the same mechanism as two existing ones").

---

### 12. Known Compromises and Follow-Up Direction (when applicable)

After writing the solution design and tasks, step back and ask:

1. **What opportunities does this work create that we're deliberately not
   taking?** Name them. A proposal that touches 3 similar call sites but only
   fixes 2 should say why the 3rd is deferred — not leave it as a silent gap
   for the next person to rediscover.

2. **What V1 pragmatism will look hacky in 6 months?** Synthetic IDs,
   duplicated patterns, string-typed enums — these are fine as conscious
   compromises, but only if named. Unnamed compromises become accidental
   architecture.

3. **What shared abstraction is emerging but not yet worth extracting?** If
   the same pattern (e.g. "collect events, build audit record, persist") now
   appears in 3+ places after this proposal, name the future extraction
   direction. Don't build it — just point at it so the next proposal can.

Format:

```markdown
## Known Compromises and Follow-Up Direction

### {Compromise name} (V1 pragmatism)
{What the compromise is, why it's acceptable now, and when/why to revisit.}

### {Emerging pattern name}
{What pattern is forming, where it appears, and what the extraction direction is.}
```

**When to skip:** Truly standalone proposals with no architectural debt and no
emerging patterns. Write "No known compromises — standalone feature." to show
you considered it.

**Why this matters:** P47 added audit to workflow engine paths but silently left
planner/enricher unaudited. P51 had to be written to close the gap. If P47 had
named "planner and enricher delegation paths are not covered — follow-up needed"
in a Known Compromises section, the gap would have been tracked from the start.

---

## Step 4: Next Steps After Writing

1. Run `/proposal-review` — mandatory before any implementation or user approval
2. Fix any P0 or P1 issues raised by the reviewer
3. Present the proposal to the user for approval
4. After approval: run `/create-github-issues` to create tracked tasks

---

## Proposal File Template

```markdown
# Proposal {NN} — {Title}

## Status: Draft

## Prerequisites
{Other proposals or infrastructure that must exist. "None" if standalone.}

## Scope
- Tasks: ~N
- Layers: {features, core, app}
- Risk: {Low/Medium/High} — {one-phrase reason}

---

## Problem Statement

{User-facing description of the problem and why it matters.
Concrete incident or observed gap.}

---

## Are We Solving the Right Problem?

**Root cause:** {Trace the symptom to its origin.}

**Alternatives dismissed:**
- {Option A}: {why insufficient or wrong}
- {Option B}: {why insufficient or wrong}

**Smallest change?** {Why this scope is necessary — or adopt the smaller approach.}

---

## Goals

- {Intent-level statement 1}
- {Intent-level statement 2}

## Non-goals

- {Explicit boundary 1}
- {Explicit boundary 2}

---

## User-Visible Changes

{2-3 sentences from the user's perspective. "No user-visible changes" is valid
for internal infrastructure.}

---

## Solution Design

{Technical approach: contracts, data flows, decisions, constraints.
No implementation code — use pseudocode for non-obvious algorithms.
API contracts (endpoints, JSON shapes, event envelopes) should be precise.}

---

## Affected Mutation Points

{Summary list of all methods that mutate the relevant state.
Group into "Needs change" and "No change needed".
Detail goes into tasks, not here.}

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | {Mergeable PR description — includes its own tests} | {layers} |
| T2 | ... | ... |

### T1 details
{Expanded description for complex tasks. Implementation hints, mutation points
covered, specific test cases.}

---

## Test Impact

### Existing tests affected
{List affected test files and what changes}

### New tests
{List new tests with how to run them}

---

## Acceptance Criteria

1. ...
2. ...
3. ...

---

## Risks

| Risk | Mitigation |
|------|------------|
| ... | ... |

---

## Alternatives Considered

{For proposals introducing new patterns. Otherwise omit with one-line note.}

---

## Known Compromises and Follow-Up Direction

{Name V1 pragmatisms, deferred opportunities, and emerging patterns.
"No known compromises — standalone feature." is valid when genuinely true.}
```

---

## Red Flags

**Never:**
- Start implementation before the proposal is written and reviewed
- Write a proposal so vague it can't be reviewed ("implement X somehow")
- Skip the acceptance criteria ("we'll know it works when it works")
- Put implementation details in the problem statement or vice versa
- Include ready-to-paste code snippets in Solution Design (contracts yes, implementation no)
- Create tasks that aren't independently mergeable
- Put tests in a separate task from the code they test

**If scope is unclear:**
- Write the problem statement and "Are We Solving the Right Problem?" first, share with the user
- Let the solution emerge from the problem, not the other way around
