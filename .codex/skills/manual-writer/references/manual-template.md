# Manual Template (Markdown)

## General Rules

- One topic per section.
- Use task-oriented or descriptive headings.
- Use numbered lists for steps.
- Use code blocks for configuration and commands.

## Structure: Single File

```markdown
# [Product Name] - User Manual

> Version: [x.y] | Last updated: [YYYY-MM-DD]

## Table of contents
- [Quick Start](#quick-start)
- [Core Tasks](#core-tasks)
- [Advanced Features](#advanced-features)
- [Settings and Configuration](#settings-and-configuration)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Glossary](#glossary)

## Quick Start
Short goal statement and 3-5 steps to first success.

## Core Tasks
### [Task 1]
Goal, when to use, steps.

### [Task 2]
Goal, when to use, steps.

## Advanced Features
### [Feature]
Description, scenarios, limitations.

## Settings and Configuration
### [Setting]
Description, options, effects.

## Troubleshooting
### Symptom: [description]
- **Cause**: ...
- **Fix**: ...

## FAQ
- **Q: ...**
- **A:** ...

## Glossary
- **Term**: definition.
```

## Structure: Multi File

```text
manual/
  index.md
  getting-started.md
  tasks/
    task-1.md
    task-2.md
  advanced/
    feature-a.md
  settings/
    configuration.md
  troubleshooting.md
  faq.md
  glossary.md
```

### index.md (example)

```markdown
# [Product Name] - User Manual

## Table of contents
- [Quick Start](getting-started.md)
- [Core Tasks](tasks/task-1.md)
- [Advanced Features](advanced/feature-a.md)
- [Settings and Configuration](settings/configuration.md)
- [Troubleshooting](troubleshooting.md)
- [FAQ](faq.md)
- [Glossary](glossary.md)
```

### Linking Conventions

- Use relative links between files.
- Add a "See also" section at the end of longer pages.
- Add "Next/Previous" in sequential documents.
