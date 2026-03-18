---
name: proposal-review
description: Use before implementing any proposal, tech design, RFC, or architecture document to catch issues before they become expensive code changes
---

# Proposal Review

Dispatch a proposal-reviewer subagent to evaluate technical proposals before implementation begins.

**Core principle:** Issues found in a proposal cost 10x less to fix than issues found in code.

## When to Use

**Mandatory:**
- Before starting implementation of any proposal/tech design/RFC
- After making significant changes to a proposal
- When a proposal has dependencies on other proposals

**Optional but valuable:**
- When a proposal feels "off" but you can't articulate why
- When two proposals seem to conflict with each other
- Before presenting a proposal to stakeholders

## How to Request

**1. Identify the proposal file(s):**
```bash
ls docs/proposals/        # list available proposals
ls docs/plans/            # or plans directory
```

**2. Collect project context:**
```bash
# Architecture rules and conventions
cat CLAUDE.md 2>/dev/null | head -80

# Related existing code (for feasibility check)
# Identify which packages/files the proposal touches

# Other proposals this one depends on
# (check "Zależności" / "Dependencies" section in the proposal)
```

**3. Dispatch proposal-reviewer subagent:**

Use Agent tool with general-purpose type, fill template at `proposal-reviewer.md`

**Placeholders:**
- `{PROPOSAL_PATH}` — path to the proposal file(s), e.g. `docs/proposals/12-scenario-tests.md`
- `{PROPOSAL_TITLE}` — short name, e.g. "Proposal 12 — Scenario Tests"
- `{CONTEXT}` — what you know about this area: related code, recent decisions, constraints

**4. Act on feedback:**
- Fix **P0 (Blocker)** issues before any implementation — proposal cannot proceed
- Fix **P1 (Major)** issues before implementation — revise and re-review
- Evaluate **P2 (Moderate)** — fix or document as known gap, then proceed
- Note **P3 (Minor)** — leave to implementer's judgment

## Example

```
[About to implement Proposal 12 — Scenario Tests]

You: Let me review the proposal before starting.

[Dispatch proposal-reviewer subagent]
  PROPOSAL_PATH: docs/proposals/12-scenario-tests.md
  PROPOSAL_TITLE: Proposal 12 — Application Scenario Tests
  CONTEXT: Depends on proposals 000+001. Project is Flutter with layered architecture.
           Existing tests use flutter_test. On-device STT with Whisper.

[Subagent returns]:
  Strengths: Comprehensive scenario coverage, good stub design
  Issues:
    P0: StubSubAgent signature wrong — won't compile
    P1: HealthChecker interval not configurable — degradation tests will be flaky
    P3: DefaultStubs() missing Available() stub on SubAgent
  Verdict: Needs revision

You: [Fix P0 and P1 in proposal, re-review]
[Proceed to implementation]
```

## Integration with Development Workflow

```
proposal-review  →  implementation  →  requesting-code-review  →  merge
```

Review the proposal *before* writing any code.
Review the code *after* writing it.
Both gates are mandatory for non-trivial work.

## Red Flags

**Never:**
- Skip review because "it's just a small proposal"
- Ignore P0 issues ("we'll figure it out during implementation")
- Proceed with P1 issues unfixed ("we'll patch it later")

**If reviewer is wrong:**
- Push back with specific technical reasoning
- Point to existing code that disproves the concern
- Update the proposal to address the confusion

See reviewer template at: proposal-review/proposal-reviewer.md
