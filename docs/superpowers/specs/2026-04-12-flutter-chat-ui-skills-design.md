# Flutter Chat UI Skills Design

## Summary

Create a small design skill stack for `FlutterAIChat` so Codex stops treating chat UI work like generic Flutter polishing and instead follows a repeatable, product-grade design workflow.

The stack consists of:

- `/.agents/skills/flutter-chat-ui-director/SKILL.md`
- `/.agents/skills/flutter-ui-review/SKILL.md`
- `docs/design/flutter-chat-ui-prompts.md`

These artifacts are intended to raise the design quality of future chat-page work by separating design direction from post-change review and by preserving project-specific aesthetic rules.

## Problem

The current project suffers from two recurring failure modes when Codex is asked to improve UI:

1. It produces safe but bland Flutter/Material output with obvious demo-app energy.
2. It changes local styling without improving overall hierarchy, rhythm, or product feel.

The user wants externalized skill/prompt support that strengthens Codex's design judgment, especially for the chat home page.

## Goals

- Improve Codex's ability to propose and implement higher-quality chat UI changes.
- Establish a stable design direction for the chat page: immersive dark, restrained, polished, AI-product-oriented.
- Introduce a review step so UI work is evaluated before being treated as complete.
- Preserve the user's design preferences in a reusable project document.

## Non-Goals

- Directly redesigning the chat page in this spec.
- Defining a full app-wide design system for every page in the product.
- Adding design tooling integrations such as Figma sync in this iteration.

## User-Approved Design Direction

### Focus

- Primary target: chat main page
- Secondary concern: the page should still fit a broader future design system

### Experience Priorities

- Raise visual sophistication first
- Also improve interaction quality where it contributes to product feel
- Avoid preserving the current visual language unless a pattern is clearly worth keeping

### Visual North Star

- Immersive dark base
- Refined, restrained product feel in the spirit of Linear / Notion precision
- Small amount of AI workbench atmosphere
- Explicitly avoid noisy cyberpunk styling, cheap gradients, or default Flutter template aesthetics

### Platform Priority

- Support all platforms
- Optimize decisions for phone-first ergonomics and reading flow
- Ensure desktop/web still feels intentional rather than stretched mobile UI

## Deliverables

### 1. `flutter-chat-ui-director` skill

Purpose: guide design generation and implementation direction for Flutter chat UI work.

Responsibilities:

- Diagnose the current page before proposing changes.
- Define a design direction before code changes begin.
- Recommend layout, hierarchy, component, and token changes.
- Translate design intent into Flutter-specific implementation constraints.
- Enforce anti-pattern avoidance.

Planned sections:

- YAML frontmatter with search-friendly trigger description
- Overview
- Design north star
- Required workflow
- Chat-page heuristics
- Flutter mapping rules
- Anti-patterns
- Output contract
- Common mistakes

### 2. `flutter-ui-review` skill

Purpose: review completed or proposed UI changes and surface structured design/UX issues.

Responsibilities:

- Evaluate visual hierarchy, rhythm, readability, consistency, and product feel.
- Review chat-specific interactions such as streaming states, input focus, and message readability.
- Grade issues by severity.
- Prevent weak “looks changed therefore complete” conclusions.

Planned sections:

- YAML frontmatter with review-oriented triggers
- Overview
- Review dimensions
- Chat-specific checklist
- Severity rules
- Output format
- False-positive guards
- Pass criteria

### 3. `flutter-chat-ui-prompts.md`

Purpose: preserve project-specific design language and reusable prompt fragments.

Responsibilities:

- Store aesthetic definition and visual principles.
- Capture chat-page rules and preferred token characteristics.
- Record anti-patterns to avoid.
- Provide reusable prompt snippets for future UI tasks.

Planned sections:

- Product aesthetic
- Visual principles
- Chat-page rules
- Token preferences
- Anti-patterns
- Prompt snippets

## Workflow Design

Future chat UI work should follow this sequence:

1. Use `flutter-chat-ui-director` to diagnose problems and define the design direction.
2. Implement the chosen changes in Flutter code.
3. Use `flutter-ui-review` to evaluate the result.
4. If review identifies directional issues, return to the director stage rather than only patching details.

This workflow intentionally separates creation from critique.

## Design Principles To Encode

The new skill stack should repeatedly reinforce these principles:

- Content first; decoration second.
- Input area is a core interaction surface, not an afterthought.
- Hierarchy, spacing, and rhythm matter more than simply changing colors.
- Dark mode should feel calm and premium, not harsh or neon.
- Chat-specific states must feel deliberate: idle, typing, streaming, reasoning, tool, empty, loading.
- The interface should feel like a mature AI product, not a generic sample app.

## Anti-Patterns To Encode

The skill stack should explicitly reject:

- Default Material look with minimal transformation
- Over-saturated blue/purple gradients
- Excessive outlines, shadows, and glassmorphism
- Pure black surfaces with harsh white text everywhere
- Message bubbles and input controls that feel like unrelated component systems
- “Improvement” that only tweaks color while preserving weak page hierarchy

## File Locations

Planned output paths:

- `/.agents/skills/flutter-chat-ui-director/SKILL.md`
- `/.agents/skills/flutter-ui-review/SKILL.md`
- `docs/design/flutter-chat-ui-prompts.md`

## Implementation Notes

- Skill descriptions must be optimized for discovery so Codex knows when to invoke them.
- The director skill should be Flutter-native in wording and avoid web-only assumptions.
- The review skill should produce concise, prioritized review output.
- The prompts document should remain lightweight and reusable, not turn into a vague essay.

## Risks

- If the skills are too abstract, Codex will still revert to generic UI advice.
- If the skills are too web-oriented, recommendations will not map cleanly to Flutter.
- If anti-patterns are too weakly stated, Codex will rationalize shallow cosmetic changes.

## Validation Plan

Once the files are written, validate them by:

1. Checking that each skill has clear triggering language.
2. Verifying the two skills have distinct responsibilities.
3. Ensuring the prompts document encodes concrete aesthetic constraints.
4. Running the relevant skill validation checks if applicable.

## Open Questions

No blocking product questions remain for this initial design. The next stage is implementation planning for the three documents themselves.
