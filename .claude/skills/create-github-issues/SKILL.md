---
name: create-github-issues
description: Use after a proposal has been approved by the user to create GitHub issues for each implementation task. Each task in the proposal's task list becomes one GitHub issue.
---

# Create GitHub Issues from Approved Proposal

After the user approves a proposal, create one GitHub issue per task from the
proposal's task list. This gives the work a trackable backlog.

**Announce at start:** "I'm using the create-github-issues skill to create tracked tasks."

**Prerequisite:** User has explicitly said the proposal is approved.
Never create issues for unapproved proposals.

---

## Step 1: Read the Proposal

```bash
cat docs/proposals/{NN}-{name}.md
```

Identify:
- Proposal title and number
- Each task in the `## Tasks` section
- Acceptance criteria (used for issue body context)

---

## Step 2: Create Issues

For each task `T{N}` in the proposal:

```bash
gh issue create \
  --title "Proposal {NN} T{N}: {task description}" \
  --body "$(cat <<'EOF'
## Context

Part of [Proposal {NN} — {Title}](docs/proposals/{NN}-{name}.md).

## Task

{Full task description from proposal}

## Acceptance Criteria (from proposal)

{Copy relevant acceptance criteria that this task contributes to}

## Definition of Done

- [ ] Implementation complete
- [ ] Tests written and passing (`flutter test && flutter analyze`)
- [ ] Architecture check passes (`flutter analyze`)
- [ ] Code review done (`/requesting-code-review`)
EOF
)" \
  --label "proposal-{NN}"
```

**Label convention:** Create label `proposal-{NN}` if it doesn't exist:
```bash
gh label create "proposal-{NN}" --color "#0075ca" --description "Proposal {NN} tasks" 2>/dev/null || true
```

---

## Step 3: Report Created Issues

After creating all issues, list them:

```bash
gh issue list --label "proposal-{NN}"
```

Report the issue numbers and URLs to the user.

---

## Step 4: Note the Workflow for Each Issue

Remind the user of the per-issue workflow:

```
For each issue:
1. Create branch: git checkout -b feat/p{NN}-t{N}-{short-name}
2. Implement the task
3. Run: flutter test && flutter analyze
4. Run: /requesting-code-review
5. Fix any issues
6. Push + create PR referencing the issue: gh pr create --title "..." --body "Closes #{issue-number}"
```

---

## Red Flags

**Never:**
- Create issues for a proposal the user hasn't approved
- Create one giant issue for the whole proposal (defeats the purpose)
- Omit the proposal link from the issue body (traceability is critical)
- Create issues and immediately start implementing without the user picking up the first one
