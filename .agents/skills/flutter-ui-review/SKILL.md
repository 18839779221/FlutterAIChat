---
name: flutter-ui-review
description: Use when reviewing, auditing, or validating Flutter chat UI changes, especially after redesigning the chat page, input bar, message list, empty states, or cross-platform layouts that need structured feedback on hierarchy, polish, interaction quality, and product feel.
---

# Flutter UI Review

## Overview

Use this skill to review proposed or completed Flutter chat UI work before treating it as done.

This skill is not for inventing a new direction from scratch. It is for identifying what still feels visually weak, inconsistent, awkward, or insufficiently polished after changes have already been proposed or implemented.

Use `docs/design/flutter-chat-ui-prompts.md` as the project-specific design baseline while reviewing.

## Review Dimensions

Evaluate the UI across these dimensions:

1. **Visual hierarchy**
   - Is there a clear primary focus?
   - Do important actions and content stand out without over-shouting?
2. **Spacing and rhythm**
   - Do layout, message spacing, and section gaps feel intentional, dense enough, and comfortable to read?
   - Is the page cramped, noisy, or uneven?
3. **Color and tonal layering**
   - Does the active theme support reading first, rather than pushing chrome or decoration first?
   - Are accents restrained and semantic?
4. **Component consistency**
   - Do bubbles, bars, buttons, cards, and sheets feel like one design system?
5. **Interaction feedback**
   - Are hover, pressed, focused, loading, and streaming states clear without being flashy?
6. **Chat readability**
   - Are long answers comfortable to scan?
   - Do message widths, line lengths, grouping, and paragraph density support extended use?
7. **Cross-platform fit**
   - Does phone use feel ergonomic?
   - Does desktop/web feel intentionally composed rather than stretched mobile UI?
8. **Product feel**
   - Does the result feel like a mature AI product, or still like a styled prototype?

## Chat-Specific Checklist

Review these chat-specific concerns every time:

- Input area feels like a primary interaction surface
- Top bar supports orientation without overpowering the screen
- User and assistant messages are distinct but coherent
- User messages read like anchors or prompts, not default bubble widgets
- Streaming and reasoning states feel integrated into the product
- Empty state feels intentional and premium
- Tool-call or system-state visuals are understandable and not noisy
- Long conversations remain readable and low-fatigue
- The page feels more like a document-reading environment than a stack of demo cards
- Mobile layout supports thumb use and quick resumption of typing
- Desktop layout uses width and spacing with intent

## Severity Rules

Classify findings using these levels:

- **P0** — breaks usability or causes major confusion
- **P1** — significantly hurts product feel or primary interaction quality
- **P2** — noticeable design debt or inconsistency worth fixing soon
- **P3** — minor polish opportunity

Prefer fewer, high-confidence findings over long generic critique lists.

## Review Output Format

When responding with this skill, provide:

1. **Overall verdict** — one short paragraph on whether the UI feels product-grade yet
2. **Top 3 issues** — the biggest remaining blockers to polish or clarity
3. **Prioritized findings** — grouped by severity (`P0` to `P3`)
4. **Minimum next pass** — the smallest set of changes that would most improve the result

Keep the review direct, specific, and grounded in what is visible on the screen.

## False-Positive Guards

Do not flag issues just because the UI is quiet or restrained.

Avoid these review mistakes:

- asking for more decoration when the problem is already solved by good hierarchy
- demanding stronger branding at the expense of readability
- recommending more motion when the interface already communicates state clearly
- criticizing consistency simply because user and assistant areas are intentionally differentiated
- pushing for redesign-level changes when only polish-level changes are justified

## Pass Criteria

A chat UI is ready to pass when all of the following are true:

- the main interaction surfaces feel deliberate and coherent
- hierarchy is clear without loud styling tricks
- the input area feels strong, comfortable, and visually anchored
- message reading is calm and sustainable over long sessions
- the active theme feels editorial and professional, not plastic or overly componentized
- inline code, quotes, and support surfaces feel chromatically intentional rather than default-beige or ad hoc
- desktop/web composition feels intentional, not stretched from mobile
- remaining issues are polish-level, not direction-level

## Common Review Traps

- confusing “different” with “better”
- rewarding cosmetic change over structural improvement
- ignoring chat-specific states while over-focusing on static screenshots
- letting generic web UI standards override Flutter chat ergonomics
- accepting a polished input bar while the message area still lacks rhythm
