# Flutter Chat UI Prompts

## Product Aesthetic

The chat experience should feel immersive, calm, and premium.

Preferred product personality:
- restrained rather than loud
- polished rather than decorative
- intelligent rather than futuristic cosplay
- product-grade rather than demo-like

Target impression:
- a mature AI tool people can stay in for long sessions
- visually intentional on phone first, but still composed on desktop and web
- light-theme-led, with dark mode as a secondary adaptation
- more like a document reader than a stack of chat widgets

## Visual Principles

- Content comes first. Decoration exists to support focus, hierarchy, and mood.
- Prioritize spacing, rhythm, and surface hierarchy before trying to improve a screen with new colors.
- Make the input area feel like the primary action surface, not an afterthought under the message list.
- Use contrast selectively. Important content and actions should stand out, but the whole screen should not shout.
- Prefer calm tonal layering over loud outlines, excessive shadows, or aggressive gradients.
- Preserve reading comfort during long conversations, especially in streaming and reasoning-heavy sessions.
- Keep visual language unified across chat bubbles, top bar, input bar, sheets, and settings entry points.
- Prefer semantic surfaces over wireframe borders. If a region can be separated by tone, do not default to outlining it.
- Floating controls may use subtle blur and lift, but should remain visually quiet and never dominate the reading area.

## Chat-Page Rules

- The chat page is a reading surface first and an interaction surface second. Both must feel deliberate.
- The top bar should provide orientation and access, but it must not dominate the page.
- Message rhythm matters: group related content cleanly, avoid noisy separators, and preserve vertical breathing room.
- User and assistant messages should be visually distinguishable without creating a childish “two toy bubbles” effect.
- User messages should feel like question anchors, not oversized chat balloons.
- Reasoning, tool-call, loading, and streaming states need their own hierarchy and tone. They should feel integrated into the product, not bolted on.
- Empty state should feel calm and premium, with a clear invitation to begin, not like placeholder scaffolding.
- Input bar should feel anchored, comfortable, and high-confidence. It should visually communicate: type here, stay here, act here.
- On desktop and web, avoid stretched-mobile emptiness. Use width, padding, and composition intentionally.
- On phone, optimize for thumb reach, message readability, and low-friction resumption of typing.

## Design Token Preferences

### Color

- Prefer paper, stone, warm gray, fog, slate, and muted ink tones over pure black.
- Use one restrained accent family at a time.
- Accent color should feel deliberate and modern, not neon.
- Use semantic surfaces with tonal separation: background, elevated surface, active surface, accent surface.
- Avoid relying on outline-only contrast when a subtle surface shift would do the job better.
- Inline code, quotes, and lightweight annotations should use cool neutral or gray-blue surfaces rather than yellow-beige chips.

### Typography

- Prefer clean, modern, neutral type with strong readability.
- Let hierarchy come from size, spacing, and weight rather than excessive color variation.
- Avoid tiny label-heavy interfaces.
- Long-form assistant content should feel comfortable to scan, not cramped.
- Current default production direction: `Anthropic Sans` for UI and Latin content, `Noto Sans SC` for packaged Chinese document reading.
- Use lighter heading weight and stable paragraph rhythm to approximate premium mobile reading rather than presentation-slide typography.

### Spacing

- Use a consistent spacing rhythm with enough breathing room to feel premium.
- Favor slightly more vertical space in chat than a generic productivity app would use.
- Keep dense utility controls grouped and visually secondary.
- Tighten message-to-message transitions when the intent is “question then answer”. The assistant reply should begin like a document continuation, not a separate module.

### Shape and Elevation

- Use medium-to-large radii, but avoid overly soft “pill everywhere” styling.
- Use elevation sparingly.
- Prefer surface contrast and tonal layers over heavy drop shadows.
- Rounded corners, borders, and surfaces should feel like one system.
- Header buttons, scroll affordances, and the input dock should share the same restrained floating-control language.

### Motion

- Motion should support clarity and state changes, not perform for attention.
- Streaming, pending, and transitioning states should feel alive but calm.
- Avoid slow, syrupy animations and flashy reveal effects.

## Anti-Patterns

Do not introduce any of the following unless there is an explicit, narrow reason:

- default Flutter or default Material sample-app look
- pure black backgrounds with stark white text everywhere
- saturated blue-purple gradients used as a shortcut to “AI feel”
- glassmorphism, neon glow, or decorative blur as a primary visual identity
- too many borders, nested cards, or redundant containers
- random accent colors without a semantic system
- user and assistant message styles that look like separate apps
- line-box / wireframe-heavy surfaces that make the UI feel plastic
- tiny controls, tiny labels, or dense toolbar clutter
- changing only colors while leaving weak page hierarchy untouched
- desktop layouts that simply stretch mobile proportions without recomposition

## Reusable Prompt Snippets

### 1. Diagnose Before Redesign

Use this before asking for implementation:

> Review the current Flutter chat page as a product designer first. Identify the 3 biggest problems in hierarchy, rhythm, and product feel. Do not write code yet. Name the visual direction, explain why it fits an AI chat product, and propose the smallest set of structural changes that would create the biggest improvement.

### 2. Generate A Directional Redesign

> Redesign this Flutter chat page in an immersive dark style that feels calm, refined, and premium. Keep the interface product-grade and restrained. Prioritize hierarchy, spacing, tonal layering, and input-bar quality over decorative effects. Avoid default Material energy, loud gradients, and gimmicky AI styling.

### 3. Focus On The Input Area

> Redesign the chat input area so it feels like the primary interaction surface of a mature AI product. Make it comfortable, high-confidence, and visually anchored. Improve shape, spacing, controls, and states without turning it into a generic form field.

### 4. Audit Chat Readability

> Review the message list for reading comfort. Evaluate bubble treatment, content width, vertical rhythm, long-answer readability, and the visual handling of streaming or reasoning states. Recommend changes that improve calmness and clarity rather than just adding style.

### 5. Force Flutter-Native Recommendations

> Give Flutter-native guidance only. Map suggestions to `ThemeData`, `ColorScheme`, typography scale, spacing tokens, reusable widgets, and surface hierarchy. Do not give CSS, Tailwind, or HTML-specific implementation advice.

### 6. Review Before Declaring Done

> Perform a strict UI review of the proposed chat-page changes. Judge visual hierarchy, spacing rhythm, color restraint, component consistency, interaction feedback, and overall product feel. Report the top 3 issues that still keep the page from feeling polished.

## External References

These references can inform future iterations, but should not override project-specific rules:

- `frontend-design` for high-level visual direction and anti-generic aesthetics
- `ui-ux-pro-max` for broader style systems, UX heuristics, and stack-aware pattern ideas
- `ui-design-review` for structured visual audit dimensions

When those sources conflict with this document, prefer this repository's chat-specific design goals.
