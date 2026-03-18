---
name: manual-writer
description: Create and edit user manuals in Markdown, including information architecture, navigation, tone, and content standards. Use when a user asks to write, organize, or improve a user manual, help guide, onboarding docs, or product documentation.
---

# Manual Writer

## Overview

Write clear, task-oriented user manuals in Markdown with a consistent structure, language, and navigation that help readers find information quickly.

## Workflow

1. Gather context or make reasonable assumptions for missing data.
2. Propose a manual structure aligned to the product and audience.
3. Write the content in Markdown following the style and navigation rules.
4. Verify completeness, terminology consistency, and usability.

## 1) Gather Context

- Identify the manual goal: onboarding, step-by-step tasks, troubleshooting, reference.
- Identify the audience: new users, admins, technical, non-technical.
- Collect scope of features/topics, platform (web/mobile/desktop), prerequisites.
- If details are missing, make reasonable assumptions and list them in an "Assumptions" section.

## 2) Manual Structure

- Choose a format:
- `Single file` for short manuals.
- `Multi file` for long manuals or multiple user journeys.
- Always include a table of contents.
- Use the template and patterns in `references/manual-template.md`.

## 3) Writing Style

- Write plainly and directly; avoid marketing language.
- Use second person and imperative voice in steps.
- Prefer short sentences and lists.
- Use consistent terminology.
- Distinguish between:
- `Tasks` (how to do something)
- `Reference` (what it is, parameters, limits)
- `Troubleshooting` (symptom -> cause -> fix)

## 4) Navigation and Usability

- Use consistent H1/H2/H3 headers.
- Add a short intro for longer sections.
- Use internal links to related topics.
- Add a "Related" or "See also" section for important topics.
- In multi-file mode, add "Next/Previous" links at the end of sequential pages.

## 5) Content Rules

- Start with "Quick Start" or "Getting Started" when appropriate.
- Add "Prerequisites" where it helps.
- Include "FAQ" only when there are real user questions.
- Include a "Glossary" if you use specialized terms.
- Add "Security and Privacy" if relevant to the product.

## 6) Quality Check

- Check term consistency and links.
- Ensure all key user journeys are documented.
- Shorten long paragraphs and remove repetition.

## References

- `references/manual-template.md` - canonical manual structure, section templates, navigation, and conventions.
