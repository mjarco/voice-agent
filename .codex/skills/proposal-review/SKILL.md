---
name: proposal-review
description: Use before implementing any proposal, tech design, RFC, or architecture document to catch issues before they become expensive code changes
---

# Proposal Review

Dispatch a proposal-reviewer subagent to evaluate technical proposals before implementation begins.

Core principle: Issues found in a proposal cost 10x less to fix than issues found in code.
Second principle: a technically complete proposal can still solve the wrong problem, so review must pressure-test framing, ownership, and source of truth.
Third principle: even a good proposal may leave important simplifications or unifications unexplored, so review should call out meaningful missed opportunities.

## When to Use

Mandatory:
- Before starting implementation of any proposal/tech design/RFC
- After making significant changes to a proposal
- When a proposal has dependencies on other proposals

Optional but valuable:
- When a proposal feels "off" but you can't articulate why
- When two proposals seem to conflict with each other
- Before presenting a proposal to stakeholders
- When a proposal appears to fix a local symptom but may be missing the underlying model

## How to Request

1. Identify the proposal file(s):
```bash
ls docs/proposals/
ls docs/plans/
```

2. Collect project context:
```bash
cat CLAUDE.md 2>/dev/null | head -80
# Read related code and dependent proposals
```

3. Dispatch proposal-reviewer subagent:
- Use template at `proposal-review/proposal-reviewer.md`
- Fill placeholders:
  - `{PROPOSAL_PATH}`
  - `{PROPOSAL_TITLE}`
  - `{CONTEXT}`

4. Treat framing checks as mandatory:
- What is the actual missing model or contract behind the symptom?
- Who owns the decision, projection, or state after the change?
- What becomes the source of truth?
- Which adjacent proposals or existing flows does this replace, extend, or conflict with?
- Could a technically correct implementation still leave the user with the same pain?
- What important improvement is the proposal intentionally not taking, and is that omission reasonable?

5. Act on feedback:
- Fix P0 before implementation
- Fix P1 before implementation
- Evaluate/fix/document P2
- Note P3 for implementer judgment

## Integration with Workflow

proposal-review -> implementation -> requesting-code-review -> merge

Review the proposal before writing code.
Review code after implementation. Both gates are mandatory for non-trivial work.

## Review Standard

Every review must explicitly pressure-test:
- `Actual Problem` — what missing model or contract causes the symptom?
- `Primary Owner` — backend, frontend, runtime, planner, manifest, etc.
- `Source of Truth` — where truth lives after the change
- `Wrong Problem Risk` — why this proposal might still be solving the wrong thing
- `Missed Opportunities` — what meaningful simplification, unification, or cleaner model is being deferred or ignored

If the proposal does not make these answerable, that is a real issue, not a style nit.

## Red Flags

Never:
- Skip review because "small proposal"
- Ignore P0/P1 and "patch later"
- Treat local completeness as proof that the framing is correct
- Accept "this feels right" without checking ownership and source of truth

If reviewer is wrong:
- Push back with specific technical reasoning and code evidence
- Update proposal text to remove ambiguity

See reviewer template at: `proposal-review/proposal-reviewer.md`
