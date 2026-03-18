---
name: proposal-authoring
description: Use when creating or significantly rewriting a technical proposal, RFC, or design document so the problem framing, ownership, source of truth, and implementation contract are explicit before review
---

# Proposal Authoring

Write proposals that are not only complete, but aimed at the right problem.

Core principle: most weak proposals fail before the solution section. They solve a visible symptom without naming the missing model, contract, owner, or source of truth.

## When to Use

Mandatory:
- Creating a new technical proposal, RFC, or architecture note
- Rewriting a proposal after major review feedback
- Splitting one proposal into multiple proposals
- Turning a design discussion into a committed document under `docs/docs/proposals/`

Use this before sending the document to `proposal-review`.

## Workflow

1. Read the relevant code and adjacent proposals first.
2. Name the symptom.
3. Name the actual missing model or contract behind the symptom.
4. Explore 2-3 problem framings, not just 2-3 solutions.
5. Decide who should own the decision, projection, or state after the change.
6. Decide the source of truth.
7. Only then write options and recommendation.
8. Identify any meaningful missed opportunities the proposal is intentionally not taking.
9. Include a short section explaining why the proposal might still be solving the wrong problem.

## Required Sections

Every non-trivial proposal should answer these, either as explicit headings or clearly labeled subsections:

- `Problem Statement`
- `Why This Is The Right Problem`
- `Alternative Problem Framings`
- `Primary Owner`
- `Source of Truth`
- `Missed Opportunities`
- `Solution Options`
- `Recommendation`
- `Affected Mutation Points`
- `Test Impact`
- `Acceptance Criteria`
- `Why This Proposal Might Be Solving The Wrong Problem`

These can be short. They must be present in substance.

## Section Guidance

### Why This Is The Right Problem

Explain:
- the visible symptom
- the missing model/contract/owner behind it
- why this is not only a local bug or UI glitch

If this section is weak, the proposal is probably too close to the symptom.

### Alternative Problem Framings

List 2-3 ways to describe the problem. Example:
- `handoff lacks output context`
- `agent work has no durable result model`
- `reviewable work is split across two workflow steps`

Then pick the framing you believe is correct and say why.

This is the fastest way to catch proposals that are about the wrong thing.

### Primary Owner

State who owns the result after the change:
- backend read model
- frontend composition layer
- workflow runtime
- planner
- manifest
- conversation/session layer

Ambiguous ownership is one of the most common causes of follow-up proposals.

### Source of Truth

Name the canonical truth after the change:
- which record, DTO, snapshot, thread, manifest field, or runtime structure
- who is allowed to derive projections from it
- what is no longer authoritative

### Why This Proposal Might Be Solving The Wrong Problem

This section is mandatory for non-trivial proposals.

Write 2-6 bullet points answering questions like:
- What if the pain comes from a different missing model?
- What if this proposal only improves freshness, not ownership?
- What if this is a UI symptom of a backend contract gap?
- What if this proposal fixes one consumer but not the underlying shared flow?

This is not performative self-doubt. It is a design safety check.

### Missed Opportunities

This section is strongly recommended for non-trivial proposals.

Explain 1-4 opportunities the proposal is **not** taking, such as:
- a shared abstraction the proposal leaves duplicated on purpose
- a cleaner identity model intentionally deferred as V2
- a broader contract unification the proposal chooses not to pull into scope
- a follow-up refactor that would become valuable if this area grows

The point is not to maximize scope. The point is to make the tradeoff explicit:
- what extra value is left on the table
- why it is not worth taking now
- whether it should become a named follow-up

This helps distinguish:
- a proposal that is appropriately scoped
- from a proposal that accidentally leaves an important simplification unexplored

## Heuristics

Pause and reframe if:
- the proposal starts from a payload tweak, cache key, or event type before naming the missing model
- the same flow already spawned 2+ nearby proposals
- the solution introduces a new object without clarifying who owns it
- the proposal relies on `later resolution` instead of naming the authoritative moment of choice
- frontend and backend responsibilities stay implicit
- the proposal solves the immediate gap but leaves a nearby duplication or shared abstraction completely unnamed

## Output Standard

A strong proposal should let a reviewer answer:
- What real problem is being solved?
- Why is this the right level to solve it?
- Who owns the result after implementation?
- Where is the truth?
- What meaningful improvement is consciously left for later?
- What could still be wrong even if implementation matches the document?

If those answers are fuzzy, revise before asking for review.
