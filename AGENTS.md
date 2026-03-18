# AGENTS.md

## Project Context

Voice Agent is an offline-first Flutter mobile app (iOS + Android) that records voice,
transcribes on-device using Whisper, and sends transcripts to the user's API.

Architecture: layered (features/ core/ app/). Stack: Flutter 3.22+, Dart 3.4+,
Riverpod, GoRouter, sqflite, Whisper (whisper_flutter_new).

See CLAUDE.md for architecture rules, coding conventions, and cross-proposal contracts.
See docs/proposals/ for feature proposals and implementation plans.

## Verification Commands

```bash
flutter analyze    # Static analysis — zero issues required
flutter test       # All tests must pass
```

Both must pass before any commit or PR.

## Skills

Local repo skills live in `.codex/skills/`. Use them when their trigger conditions match the task.

### Available skills

#### Design & Planning
- brainstorming: Use before any creative work — creating features, building components, adding functionality. Explores intent, requirements, and design before implementation. (file: .codex/skills/brainstorming/SKILL.md)
- proposal-authoring: Use when creating or rewriting a technical proposal so problem framing, ownership, and contracts are explicit before review. (file: .codex/skills/proposal-authoring/SKILL.md)
- proposal-review: Use before implementing any proposal to catch issues before they become expensive code changes. (file: .codex/skills/proposal-review/SKILL.md)
- writing-plans: Use when you have a spec or requirements for a multi-step task, before touching code. (file: .codex/skills/writing-plans/SKILL.md)

#### Implementation
- test-driven-development: Use when implementing any feature or bugfix, before writing implementation code. (file: .codex/skills/test-driven-development/SKILL.md)
- executing-plans: Use when you have a written implementation plan to execute with review checkpoints. (file: .codex/skills/executing-plans/SKILL.md)
- subagent-driven-development: Use when executing implementation plans with independent tasks in the current session. (file: .codex/skills/subagent-driven-development/SKILL.md)
- dispatching-parallel-agents: Use when facing 2+ independent tasks that can be worked on without shared state. (file: .codex/skills/dispatching-parallel-agents/SKILL.md)
- systematic-debugging: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes. (file: .codex/skills/systematic-debugging/SKILL.md)

#### Review & Completion
- requesting-code-review: Use when completing tasks, implementing major features, or before merging. (file: .codex/skills/requesting-code-review/SKILL.md)
- receiving-code-review: Use when receiving code review feedback — requires technical rigor, not performative agreement. (file: .codex/skills/receiving-code-review/SKILL.md)
- verification-before-completion: Use before claiming work is complete — run verification commands and confirm output before any success claims. (file: .codex/skills/verification-before-completion/SKILL.md)
- finishing-a-development-branch: Use when implementation is complete and you need to decide how to integrate — merge, PR, or cleanup. (file: .codex/skills/finishing-a-development-branch/SKILL.md)

#### Git & Workflow
- using-git-worktrees: Use when starting feature work that needs isolation from current workspace. (file: .codex/skills/using-git-worktrees/SKILL.md)

#### Meta
- using-superpowers: Use when starting any conversation — establishes how to find and use skills. (file: .codex/skills/using-superpowers/SKILL.md)
- skill-creator: Guide for creating effective skills. (file: .codex/skills/skill-creator/SKILL.md)
- skill-installer: Install skills from a curated list or GitHub repo. (file: .codex/skills/skill-installer/SKILL.md)
- writing-skills: Use when creating or editing skills. (file: .codex/skills/writing-skills/SKILL.md)

### How to use skills
- If the user names a skill or the task clearly matches one of the triggers above, open the matching `SKILL.md` and follow the instructions.
- Use process skills first when multiple skills apply. Examples: `brainstorming` before implementation, `systematic-debugging` before fixing unexpected behavior.
- Keep skill usage local to the current task. Load only the instructions needed.
