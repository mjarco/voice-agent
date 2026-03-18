---
name: structural-health-check
description: >
  Analyze a Dart class or file for structural health: responsibility count, method sprawl,
  dependency fan-in, constructor bloat, and growth trajectory. Use BEFORE implementing a
  feature that adds methods/responsibilities to a large class, or AFTER implementation
  when a file exceeds ~400 LOC. Gives a stop/proceed signal and concrete split plan.
  TRIGGER: when adding >2 methods to a class that already has >10 methods, or when a file
  exceeds 500 LOC, or when a constructor takes >6 injected dependencies.
---

# Structural Health Check

Proactive analysis of a Dart class's structural health to catch god-object growth
before it becomes entrenched. This skill answers: "Should I stop feature work
and split this class first?"

## When to Use

**Mandatory (auto-trigger):**
- Before implementing a proposal that adds ≥3 methods to a class with ≥10 existing methods
- When a file exceeds 500 LOC after your changes
- When a constructor takes ≥7 injected dependencies (services/repositories)

**Recommended:**
- As part of `/proposal-review` — check target classes the proposal will modify
- Before creating a PR that significantly grows a single class
- When you notice a class doing "one more thing" beyond its original scope

**Not needed for:**
- New classes being created from scratch (<200 LOC)
- Pure function files (no class methods)
- Test files

## Analysis Process

### Phase 1 — Measure

Collect quantitative metrics for the target class. Use these exact commands:

```bash
# 1. Method count (public + private) for the class
grep -c 'void \|Future<\|Stream<\|String \|int \|bool \|List<\|Map<\|dynamic ' lib/path/to/file.dart

# 2. Total LOC
wc -l lib/path/to/file.dart

# 3. Constructor parameter count (injected dependencies)
grep -A 30 'class ClassName' lib/path/to/file.dart | head -40

# 4. Service/repository dependencies (how many does the class hold?)
grep -E '^\s+final\s+\w+' lib/path/to/file.dart

# 5. Growth trajectory: LOC at key commits
git log --oneline --follow lib/path/to/file.dart | head -20

# 6. Responsibility inventory: distinct method names
grep -E '^\s+(void|Future|Stream|String|int|bool|List|Map|dynamic|Widget)\s' lib/path/to/file.dart | sort
```

### Phase 2 — Classify Responsibilities

Group the class's methods into **responsibility clusters**. A responsibility is
a cohesive set of methods that serve one concern. Common Flutter patterns:

- **UI Building**: build, buildXxx widgets
- **State Management**: state transitions, notifyListeners
- **Data Loading**: fetch, load, refresh
- **Event Handling**: onTap, onChanged, handleXxx
- **Navigation**: push, pop, route
- **Validation**: validate, check, verify
- **Persistence**: save, load, delete, cache
- **Network**: post, get, sync, retry

Count the distinct clusters. Each cluster = 1 responsibility.

### Phase 3 — Score

Apply thresholds. Each metric is green/yellow/red:

| Metric | Green | Yellow | Red |
|--------|-------|--------|-----|
| Total methods | ≤12 | 13–20 | >20 |
| Total LOC (file) | ≤400 | 401–800 | >800 |
| Constructor args | ≤5 | 6–8 | >8 |
| Dependencies | ≤4 | 5–7 | >7 |
| Responsibility clusters | ≤3 | 4–5 | >5 |
| LOC growth rate | ≤50% per feature | 51–100% | >100% |

**Overall verdict:**
- **All green** → Proceed. Class is healthy.
- **Any yellow, no red** → Proceed with caution. Note the yellow metrics — next feature that grows them should trigger a split.
- **1 red** → Warning. Consider splitting before adding more. If the current task is small, proceed but file an issue for the split.
- **≥2 red** → **Stop.** Split the class before continuing feature work. The cost of splitting now is lower than the cost of splitting later.

### Phase 4 — Recommend Split (if yellow/red)

When the verdict is not all-green, provide a concrete split plan:

1. **For each responsibility cluster with ≥3 methods**, propose a new class:
   - Name: `{Concern}Service` or `{Concern}Widget` (e.g., `SyncQueueWorker`)
   - Methods: list which methods move
   - Dependencies: which services it needs (subset of current constructor)

2. **Show the resulting constructor** for the slimmed-down original class.

3. **Estimate effort**: "This split touches N call sites and requires M new classes."

4. **Suggest ordering**: which cluster to extract first (lowest coupling = first).

## Output Format

```markdown
## Structural Health: {ClassName}

**File(s):** {paths}
**Verdict:** 🟢 Healthy / 🟡 Caution / 🟠 Warning / 🔴 Stop and split

### Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Methods | N | 🟢/🟡/🔴 |
| LOC | N | 🟢/🟡/🔴 |
| Constructor args | N | 🟢/🟡/🔴 |
| Dependencies | N | 🟢/🟡/🔴 |
| Responsibility clusters | N | 🟢/🟡/🔴 |
| Growth (last feature) | +N% | 🟢/🟡/🔴 |

### Responsibility Clusters

1. **{ClusterName}** (N methods): method1, method2, ...
2. **{ClusterName}** (N methods): method1, method2, ...
...

### Recommendation

{If green: "Class is healthy. No action needed."}

{If yellow/red: concrete split plan with new classes, method assignments,
 dependency subsets, and suggested extraction order.}
```

## Integration Points

- **During `/proposal-review`**: reviewer should run this check on any class the
  proposal adds ≥2 methods to.
- **During `/review-pr`**: if the PR grows a single class by ≥3 methods or ≥100 LOC,
  flag it and run this check.

## Red Flags

**Never:**
- Skip health check for classes touching multiple concerns
- Ignore constructor bloat ("it's just one more dependency")
- Let a file grow past 800 LOC without splitting
