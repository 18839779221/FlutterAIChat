---
name: flutter-chat-ui-director
description: Use when redesigning, refining, or upgrading Flutter chat interfaces, especially the main chat page, input bar, message list, or chat-related surfaces that need stronger visual direction, better hierarchy, more premium product feel, or less generic Material styling.
---

# Flutter Chat UI Director

## Overview

Use this skill to set design direction before editing Flutter chat UI code.

This skill is for product-level Flutter chat work, not generic web design and not superficial recoloring. Its job is to diagnose what feels weak, name a clear visual direction, and translate that direction into Flutter-native guidance the implementation can follow.

Use the repository prompts at `docs/design/flutter-chat-ui-prompts.md` as the local source of truth for aesthetic direction.

## Design North Star

Treat the desired chat experience as:

- document-first rather than widget-first
- light-theme-led, with dark mode as a secondary adaptation
- professional, quiet, and information-dense
- readable for long sessions before it is decorative
- AI-native through structure and clarity, not gradient cosplay
- phone-first in ergonomics, but intentional on desktop and web

Design for sustained reading, high content density, low visual fatigue, and an input area that does not break the editorial feel.

## Required Workflow

Do not jump directly into code edits.

For each request, work in this order:

1. **Diagnose the current screen**
   - Identify the 3 biggest issues in hierarchy, rhythm, and product feel.
   - Name what feels generic, noisy, cramped, weak, or visually disconnected.
2. **Name the visual direction**
   - Describe the intended direction in one short phrase.
   - Explain why that direction fits a Flutter AI chat product.
3. **Define structural changes**
   - Identify the smallest set of layout, spacing, surface, and component changes that will create the biggest improvement.
4. **Map to Flutter**
   - Translate direction into `ThemeData`, `ColorScheme`, typography scale, spacing tokens, surface roles, and reusable widget changes.
5. **Only then suggest implementation**
   - Keep recommendations specific to Flutter widgets and project structure.

If the request is vague, still diagnose first rather than producing generic “modernize the UI” advice.

## Chat-Page Heuristics

### Top Bar

- Keep the top bar useful but visually subordinate to the conversation.
- Use it for orientation, group title, and lightweight controls.
- Avoid turning it into the loudest region on the screen.

### Message List

- Preserve reading rhythm through spacing, grouping, and predictable width.
- Distinguish user and assistant content clearly, but avoid playful bubble theatrics or toy-like contrast.
- Long assistant replies must remain comfortable to scan.
- Reasoning, tool, loading, and streaming states must feel like part of the same system.
- Prefer the feel of a document reader with conversational anchors, not a stack of chat cards.

### Input Area

- Treat the input bar as a primary interaction surface.
- It should feel anchored, confident, and pleasant to return to repeatedly.
- Improve comfort through restraint, alignment, and calm tonal separation.
- Secondary controls should support the composer, not compete with it.
- Avoid chunky trays, layered borders, or “plastic” floating form styling when the surrounding page is editorial.

### Empty and Transitional States

- Empty state should feel intentional and calm, not like placeholder scaffolding.
- Loading and streaming states should feel alive but restrained.
- Use motion and surface changes to communicate state without visual noise.

### Cross-Platform Composition

- On phone, optimize for reach, readability, and easy typing.
- On desktop/web, avoid stretched mobile proportions.
- Use content width, edge padding, and composition to make larger screens feel designed.

## Flutter Mapping Rules

Map design recommendations into Flutter-native concepts:

- **Color:** use semantic roles through `ColorScheme` and surface layering, not ad hoc hex scattered through widgets.
- **Typography:** define a readable scale and weight hierarchy; avoid solving hierarchy with color alone.
- **Spacing:** prefer a repeatable spacing rhythm and reuse it across message items, bars, and sheets.
- **Shape:** keep radius decisions consistent across bubbles, input containers, buttons, and cards.
- **Components:** prefer reusable chat-specific widgets over one-off visual tweaks in page files.
- **State:** account for idle, focused, disabled, loading, streaming, reasoning, and tool-related states.

Do not output CSS, Tailwind, HTML layout advice, or web-only implementation details unless the user explicitly asks for web-specific adaptation.

## Anti-Patterns

Do not recommend or normalize:

- default Material sample-app styling
- pure-black backgrounds with harsh white text everywhere
- blue-purple gradient shortcuts for “AI” identity
- heavy borders, nested containers, and gratuitous cards
- glassmorphism or decorative blur as the main personality
- changing only colors while leaving hierarchy and rhythm weak
- mobile-first layouts stretched to desktop without recomposition
- input bars that feel like generic forms instead of core product controls
- wireframe-heavy surfaces that make the UI feel plastic rather than editorial
- solving document readability with oversized cards instead of typography and spacing

## Output Contract

When responding with this skill, provide:

1. **Diagnosis** — the biggest visual and interaction problems
2. **Direction** — one named design direction and why it fits
3. **Structural moves** — the highest-leverage layout and surface changes
4. **Flutter mapping** — how to express the direction in Flutter terms
5. **Implementation priorities** — what to change first, second, and later

Keep output concise, opinionated, and specific.

## Common Mistakes

- Giving generic “make it modern” advice with no point of view
- Solving a hierarchy problem by swapping colors only
- Making user and assistant messages different without making them coherent
- Over-designing decorative states while leaving the input area weak
- Importing web-centric design guidance without converting it to Flutter concepts
- Treating dark mode as pure black plus bright accent instead of tonal layering
