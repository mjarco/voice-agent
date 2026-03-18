---
name: architecture-review
description: >
  Review a proposal's architectural impact: dependency rule compliance, layer placement
  of new types/ports/adapters, coupling path analysis, naming convention adherence,
  and structural health of modified types. Use AFTER /proposal-review passes content
  review, to catch architecture violations before implementation. Complements
  /proposal-review (content correctness) and /structural-health-check (per-type growth).
---

# Architecture Review

Dispatch an architecture-reviewer subagent to evaluate a proposal's fit within the
project's layered architecture (features/core/app) before implementation begins.

**Core principle:** `/proposal-review` catches content problems (wrong interface,
missing edge case). This skill catches *structural* problems (wrong layer, new
coupling path, naming violation) that compile fine but erode architecture over time.

**Announce at start:** "I'm using the architecture-review skill to check architectural fit."

## When to Use

**Mandatory:**
- Before implementing any proposal that introduces new types, ports, or adapters
- Before implementing any proposal that touches ≥2 architectural layers
- When `/proposal-review` raises concerns about architecture fit (Dimension 8)

**Recommended:**
- When a proposal adds a new package or moves code between packages
- When a proposal introduces a new cross-cutting concern (events, middleware, DTOs)
- After significant proposal revisions that change the layer placement of types

**Not needed for:**
- Proposals that only modify existing code within a single layer
- Documentation-only or config-only changes
- Test-only changes

## How to Request

**1. Identify the proposal:**
```bash
ls docs/proposals/        # list available proposals
```

**2. Dispatch architecture-reviewer subagent:**

Use Agent tool with general-purpose type, fill template at `architecture-reviewer.md`

**Placeholders:**
- `{PROPOSAL_PATH}` — path to the proposal file(s)
- `{PROPOSAL_TITLE}` — short name
- `{CONTEXT}` — which layers are touched, any known architectural concerns

**3. Act on feedback:**
- **P0 (Blocker):** Dependency rule violation, domain importing application — must fix
- **P1 (Major):** Wrong layer placement, missing port, naming violation — fix before impl
- **P2 (Moderate):** Suboptimal placement, unnecessary abstraction — fix or document
- **P3 (Minor):** Naming preference, package organization suggestion — implementer's call

## Integration with Development Workflow

```
/create-proposal → /proposal-review → /architecture-review → implement → /review-pr
```

Run after `/proposal-review` passes (no P0/P1 remaining). Architecture review
assumes the proposal content is correct and focuses on structural fit.

## Example

```
[Proposal 47 — Agent Audit Trail passed content review]

You: Let me check the architectural fit.

[Dispatch architecture-reviewer subagent]
  PROPOSAL_PATH: docs/proposals/47-agent-audit-trail.md
  PROPOSAL_TITLE: Proposal 47 — Agent Audit Trail
  CONTEXT: Adds AgentTaskSpec and StepAuditRecord to application/engine.
           Moves prompt assembly from infrastructure to engine.
           Adds new SQLite table + repository port.

[Subagent returns]:
  Dependency rule: OK — no violations
  Layer placement:
    P2: AgentTaskSpec uses map[string]any — acceptable in application but
        consider typed fields if it grows
  Coupling paths:
    P1: Engine now owns prompt format string — all 3 adapters must strip
        their buildPrompt(). Verify no adapter-specific prompt logic remains.
  Structural health:
    Warning: WorkflowRunner already at 18 methods — T4 adds 2 more.
    Recommend running /structural-health-check on WorkflowRunner.
  Verdict: Proceed with caution (1 P1)

You: [Fix P1, re-review or proceed]
```

## Red Flags

**Never:**
- Skip architecture review for proposals touching multiple layers
- Ignore dependency rule violations ("it's just one import")
- Accept feature types that bypass the core layer or import directly from other features

**If reviewer is wrong:**
- Point to existing code that follows the same pattern
- Reference CLAUDE.md rules that support the approach
- Update the proposal to clarify the architectural rationale

See reviewer template at: architecture-review/architecture-reviewer.md
