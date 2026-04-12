# Flutter Chat UI Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-specific Flutter chat UI design skill stack that improves future chat-page redesign work through design-direction guidance, review guidance, and reusable prompts.

**Architecture:** Create three text artifacts with separate responsibilities. The prompts document captures project-specific aesthetic rules. The `flutter-chat-ui-director` skill guides design direction and implementation framing for future UI work. The `flutter-ui-review` skill audits completed or proposed UI changes using chat-specific design criteria.

**Tech Stack:** Markdown documentation, Codex skill format (`SKILL.md`), local skill directories under `/.agents/skills`, project docs under `docs/`

---

## File Structure

- Create: `docs/design/flutter-chat-ui-prompts.md`
  - Stores the long-lived design memory for this repository: aesthetic direction, visual principles, chat-page rules, anti-patterns, and reusable prompt snippets.
- Create: `.agents/skills/flutter-chat-ui-director/SKILL.md`
  - Defines when and how Codex should act as the design-direction skill for Flutter chat UI work.
- Create: `.agents/skills/flutter-ui-review/SKILL.md`
  - Defines when and how Codex should review completed or proposed Flutter chat UI changes.
- Reference: `docs/superpowers/specs/2026-04-12-flutter-chat-ui-skills-design.md`
  - Approved design source for this implementation.

## Task 1: Write the reusable prompts document

**Files:**
- Create: `docs/design/flutter-chat-ui-prompts.md`
- Reference: `docs/superpowers/specs/2026-04-12-flutter-chat-ui-skills-design.md`

- [ ] **Step 1: Write the failing test (documentation acceptance checklist)**

Create a checklist in the working notes confirming the prompts file must include:
- product aesthetic
- visual principles
- chat-page rules
- token preferences
- anti-patterns
- reusable prompt snippets

- [ ] **Step 2: Verify RED**

Open the target path and confirm `docs/design/flutter-chat-ui-prompts.md` does not exist yet.
Expected: missing file, so the acceptance checklist is currently failing.

- [ ] **Step 3: Write the minimal implementation**

Draft `docs/design/flutter-chat-ui-prompts.md` with concise, reusable sections aligned to the approved design direction:
- immersive dark / restrained / polished / AI-product feel
- phone-first while preserving desktop intention
- hierarchy, spacing, and rhythm over cosmetic recoloring
- explicit anti-patterns for cheap gradients, default Material feel, and disconnected chat components

- [ ] **Step 4: Verify GREEN**

Open the document and confirm every required section is present and the content is project-specific rather than generic design advice.

## Task 2: Write the director skill

**Files:**
- Create: `.agents/skills/flutter-chat-ui-director/SKILL.md`
- Reference: `docs/design/flutter-chat-ui-prompts.md`
- Reference: `docs/superpowers/specs/2026-04-12-flutter-chat-ui-skills-design.md`

- [ ] **Step 1: Write the failing test (skill acceptance checklist)**

Define the acceptance checklist for the director skill:
- valid skill frontmatter with only `name` and `description`
- trigger language focused on Flutter chat UI redesign / refinement work
- workflow that diagnoses before implementing
- Flutter-native mapping guidance
- anti-patterns and output contract

- [ ] **Step 2: Verify RED**

Confirm `.agents/skills/flutter-chat-ui-director/SKILL.md` does not exist yet.
Expected: missing file.

- [ ] **Step 3: Write the minimal implementation**

Create the skill with focused sections:
- overview
- design north star
- required workflow
- chat-page heuristics
- Flutter mapping
- anti-patterns
- output contract
- common mistakes

The body should be concise, Flutter-specific, and compatible with local skill conventions.

- [ ] **Step 4: Verify GREEN**

Review the file and confirm:
- frontmatter is valid and minimal
- the skill reads as Flutter chat guidance rather than generic web design guidance
- the workflow clearly separates diagnosis, direction, and implementation framing

## Task 3: Write the review skill

**Files:**
- Create: `.agents/skills/flutter-ui-review/SKILL.md`
- Reference: `docs/design/flutter-chat-ui-prompts.md`
- Reference: `docs/superpowers/specs/2026-04-12-flutter-chat-ui-skills-design.md`

- [ ] **Step 1: Write the failing test (skill acceptance checklist)**

Define the acceptance checklist for the review skill:
- valid frontmatter
- clear trigger language for UI review / design audit / polish checks
- review dimensions covering hierarchy, spacing, color, consistency, interaction feedback, readability, cross-platform fit, and product feel
- chat-specific checklist
- severity rules and pass criteria

- [ ] **Step 2: Verify RED**

Confirm `.agents/skills/flutter-ui-review/SKILL.md` does not exist yet.
Expected: missing file.

- [ ] **Step 3: Write the minimal implementation**

Create the review skill with concise but operational sections:
- overview
- review dimensions
- chat-specific checklist
- severity rules
- review output format
- false-positive guards
- pass criteria

- [ ] **Step 4: Verify GREEN**

Review the file and confirm it critiques polish and UX quality without demanding unnecessary redesign work.

## Task 4: Validate the three artifacts together

**Files:**
- Review: `docs/design/flutter-chat-ui-prompts.md`
- Review: `.agents/skills/flutter-chat-ui-director/SKILL.md`
- Review: `.agents/skills/flutter-ui-review/SKILL.md`
- Reference: `docs/superpowers/specs/2026-04-12-flutter-chat-ui-skills-design.md`

- [ ] **Step 1: Cross-check responsibilities**

Verify the prompts document stores durable design memory, the director skill guides creation, and the review skill audits outcomes.

- [ ] **Step 2: Check skill discoverability**

Review both skill descriptions and make sure they clearly signal when Codex should invoke them.

- [ ] **Step 3: Check consistency**

Ensure all three artifacts share the same visual north star, anti-patterns, and chat-page priorities.

- [ ] **Step 4: Record follow-up**

Note any future optional improvements, such as refining installed external skill descriptions or adding repository-specific review examples.
