# Skill: Review Pull Request

When the user invokes `/review-pr`, perform a structured code review of the specified PR.

## Invocation

```
/review-pr <PR-number>              # review PR in current repo
/review-pr <owner>/<repo>#<number>  # review PR in another repo
/review-pr                          # if no number given, ask the user
```

## Process

### Phase 1 — Load

Fetch all PR data using `gh`:

```bash
gh pr view <number> --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,state,reviewDecision,labels,milestone
gh pr diff <number>
gh pr view <number> --json reviews,comments,reviewRequests
```

Also run locally if the branch is checked out:
```bash
flutter test && flutter analyze 2>&1 | tail -30   # surface any failing checks
```

### Phase 2 — Orient

Before reviewing, understand the context:

1. **Size assessment**:
   - < 200 lines: deep line-by-line review
   - 200–500 lines: focus on logic + interfaces, sample tests
   - \> 500 lines: ask the user if they want a full review or focused review on a specific area

2. **Purpose**: Read the PR title and description. If the description is missing or unclear, flag it as the first comment.

3. **Scope check**: Does the diff match what the title claims? Flag scope creep or missing pieces.

### Phase 3 — Review

Evaluate the diff against these dimensions **in order**:

#### Correctness
- Does the logic implement what the description says?
- Are all error paths handled?
- Are there off-by-one errors, nil dereferences, or race conditions?
- Do tests cover the changed behavior?

#### Architecture
- Does the dependency rule hold? (features → core, not features → features)
- Are new external dependencies properly abstracted?
- Is any business logic in infrastructure/service layers?
- **Structural health:** If the PR adds ≥3 methods or ≥100 LOC to a single type/file,
  check current metrics (total methods, LOC, constructor args). If any metric is in
  the red zone (>20 methods, >800 LOC, >8 constructor args, >5 responsibility clusters),
  flag as **[blocker]**: "Type {X} exceeds structural health thresholds. Run
  `/structural-health-check` and split before merging."

#### Code quality
- Naming: clear, consistent, follows project conventions?
- Complexity: functions/methods doing one thing?
- Dead code, unused variables, commented-out code?
- Error messages: actionable, not generic?

#### Tests
- New behavior has tests?
- Tests use Flutter testing conventions (widget tests, unit tests)?
- Tests test behavior, not implementation details?

#### Security
- No hardcoded secrets, tokens, credentials?
- User input validated at boundaries?
- No SQL injection, command injection vectors?

#### Hygiene
- Commit messages follow conventional commits format?
- No TODO without a linked issue?
- No debugging artifacts (print(), debugPrint(), console.log)?

### Phase 4 — Draft Comments

For each issue found, draft a comment with this structure:

```
**[severity]** Short description of the issue.

<location: file:line if applicable>

Explanation of why this is a problem.

Suggestion: concrete fix or alternative approach.
```

Severity levels:
- **[blocker]** — must fix before merge (correctness, security, arch violations)
- **[suggestion]** — worth fixing, but not a blocker
- **[nit]** — minor style/naming, low priority
- **[question]** — clarification needed before forming an opinion

### Phase 5 — Present

Present findings as a structured summary:

```
## PR Review: <title> (#<number>)

**Verdict**: ✅ Approve / ⚠️ Approve with suggestions / ❌ Request changes

**Stats**: +X / -Y lines across N files

### Blockers (must fix)
...

### Suggestions
...

### Nits
...

### Questions
...
```

Ask the user:
- **Post all comments** — post every comment to GitHub via `gh pr review`
- **Review together** — go through comments one by one, user decides which to post
- **Copy to clipboard** — copy the summary without posting
- **Discard** — review stays local

### Phase 6 — Post (if approved)

```bash
# Post inline comments + overall review decision
gh pr review <number> --request-changes --body "<overall summary>"
# or
gh pr review <number> --approve --body "<overall summary>"
# or
gh pr review <number> --comment --body "<overall summary>"
```

For inline file comments use:
```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --method POST \
  --field body="<summary>" \
  --field event="REQUEST_CHANGES" \
  --field 'comments[][path]=<file>' \
  --field 'comments[][position]=<position>' \
  --field 'comments[][body]=<comment>'
```

## Rules

- Never approve a PR with a **[blocker]** finding unless the user explicitly overrides.
- Never post comments without user confirmation (Phase 5).
- If `flutter test` or `flutter analyze` fails locally, that is always a **[blocker]**.
- Be constructive: every **[blocker]** and **[suggestion]** must include a proposed fix or direction.
- Keep **[nit]** comments brief — one sentence max.
