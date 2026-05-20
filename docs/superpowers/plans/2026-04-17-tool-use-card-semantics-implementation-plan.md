# Tool Use Card Semantics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework tool-use rendering so context-gathering tools collapse into low-noise inline steps, external-action tools surface explicit outcome cards, and AskUserQuestion adopts the same workflow language.

**Architecture:** Keep the current message persistence and turn loop intact, but insert a UI-facing semantic projection layer between `AssistantTurnBlock` payloads and widgets. Use that projection to classify each tool block into presentation variants such as inline step, active step, confirmation step, outcome card, exception card, and interaction card. Refactor rendering incrementally so existing `toolWorkflow` / `toolResultSummary` data can keep flowing while the UI becomes semantics-driven.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test

---

## File Boundaries

### New Files

- `lib/models/chat/tool_card_presentation_variant.dart`
  - Semantic enum and lightweight helpers describing UI-facing card variants.
- `lib/models/chat/tool_card_presentation_model.dart`
  - Normalized presentation model derived from workflow steps or tool results.
- `lib/services/tool_card_presentation_mapper.dart`
  - Maps `ToolWorkflowStep`, `ToolResult`, and message payload context to presentation variants and compact display fields.
- `lib/widgets/chat_blocks/tool_inline_step_row.dart`
  - Low-height row for collapsed context-gathering tool steps/results.
- `lib/widgets/chat_blocks/tool_outcome_card.dart`
  - Explicit result card for external actions and stage outputs.
- `lib/widgets/chat_blocks/tool_exception_card.dart`
  - Expanded failure card for actionable or user-visible exceptions.
- `test/services/tool_card_presentation_mapper_test.dart`
- `test/widgets/chat_blocks/tool_inline_step_row_test.dart`
- `test/widgets/chat_blocks/tool_outcome_card_test.dart`
- `test/widgets/chat_blocks/tool_exception_card_test.dart`

### Modified Files

- `lib/services/chat_block_builder.dart`
  - Preserve current payloads, but add any minimal metadata needed by presentation mapping.
- `lib/models/chat/tool_workflow_step.dart`
  - Add comments and any small helpers required to support semantic mapping.
- `lib/models/tool/tool_result.dart`
  - Add comments and any safe helpers for outcome/failure classification.
- `lib/tools/core/tool_display_names.dart`
  - Keep stable user-facing tool names for all variants.
- `lib/widgets/chat_blocks/tool_workflow_card.dart`
  - Support emphasis tiers for inline, active, and confirmation steps.
- `lib/widgets/chat_blocks/tool_result_summary_row.dart`
  - Either slim down into a compatibility wrapper or delegate to new variant widgets.
- `lib/widgets/interaction/ask_user_question_card.dart`
  - Refactor from generic form card into workflow-style interaction card.
- `lib/widgets/chat_message_list.dart`
  - Route tool workflow and tool result blocks through the semantic mapper and variant widgets.
- `lib/theme/app_theme_spec.dart`
  - Add any missing semantic roles needed for outcome and exception surfaces without breaking current themes.
- `test/services/chat_block_builder_test.dart`
- `test/widgets/chat_message_list_test.dart`
- `test/widgets/chat_blocks/chat_blocks_test.dart`
- `test/widgets/interaction/ask_user_question_card_test.dart`

### Docs To Update After Code Lands

- `README.md`
- `AGENTS.md`
- `docs/superpowers/specs/2026-04-17-tool-use-card-semantics-design.md`

---

## Task 1: Add Semantic Presentation Models

**Files:**
- Create: `lib/models/chat/tool_card_presentation_variant.dart`
- Create: `lib/models/chat/tool_card_presentation_model.dart`
- Modify: `lib/models/chat/tool_workflow_step.dart`
- Modify: `lib/models/tool/tool_result.dart`
- Test: `test/services/tool_card_presentation_mapper_test.dart`

- [ ] **Step 1: Write failing mapper-model tests**

Add tests that define the desired variants before implementation:

```dart
test('maps web_search success to inlineStep', () {
  final result = ToolResult(
    toolName: 'web_search',
    status: ToolExecutionStatus.success,
    summary: '已执行联网搜索',
    data: {'query': 'planner', 'results': []},
  );

  final model = ToolCardPresentationMapper.mapResult(result);

  expect(model.variant, ToolCardPresentationVariant.inlineStep);
});

test('maps create_reminder success to outcomeCard', () {
  final result = ToolResult(
    toolName: 'create_reminder',
    status: ToolExecutionStatus.success,
    summary: '已发起提醒创建：设计评审',
    data: {'title': '设计评审', 'dueAt': '2026-04-18T09:00:00Z'},
  );

  final model = ToolCardPresentationMapper.mapResult(result);

  expect(model.variant, ToolCardPresentationVariant.outcomeCard);
});
```

- [ ] **Step 2: Run the mapper test to verify it fails**

Run:

```bash
fvm flutter test test/services/tool_card_presentation_mapper_test.dart
```

Expected: FAIL because the semantic model and mapper do not exist yet.

- [ ] **Step 3: Implement the semantic enum and normalized model**

Implement:

- `ToolCardPresentationVariant`
- `ToolCardPresentationModel`
- Small helpers for compact title, status label, and optional detail fields

Keep the model presentation-focused; do not duplicate raw payload JSON wholesale.

- [ ] **Step 4: Add helper methods on workflow/result models**

Add only minimal helpers needed for classification, such as:

- whether a workflow step is confirmation-focused
- whether a result is a failure with actionable user impact
- whether a tool belongs to the context-gathering family

- [ ] **Step 5: Re-run the mapper-model test**

Run:

```bash
fvm flutter test test/services/tool_card_presentation_mapper_test.dart
```

Expected: PASS for the model-level expectations.

- [ ] **Step 6: Commit the semantic model layer**

```bash
git add \
  lib/models/chat/tool_card_presentation_variant.dart \
  lib/models/chat/tool_card_presentation_model.dart \
  lib/models/chat/tool_workflow_step.dart \
  lib/models/tool/tool_result.dart \
  test/services/tool_card_presentation_mapper_test.dart
git commit -m "feat: add tool card presentation models"
```

---

## Task 2: Build the Semantic Mapper

**Files:**
- Create: `lib/services/tool_card_presentation_mapper.dart`
- Modify: `lib/tools/core/tool_display_names.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Test: `test/services/tool_card_presentation_mapper_test.dart`
- Test: `test/services/chat_block_builder_test.dart`

- [ ] **Step 1: Extend tests with real classification rules**

Add failing tests covering:

- `search_chat_history` success -> `inlineStep`
- running `fetch_webpage` workflow step -> `focusedActiveStep`
- awaiting-confirmation `create_calendar_event` -> `confirmationStep`
- success `save_note` -> `outcomeCard`
- `missing_api_key` web search failure -> `exceptionCard` only if it blocks user understanding

- [ ] **Step 2: Run the mapper and block-builder tests to confirm failure**

Run:

```bash
fvm flutter test test/services/tool_card_presentation_mapper_test.dart
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: FAIL because the classification rules are not implemented.

- [ ] **Step 3: Implement the mapper**

Implement `ToolCardPresentationMapper` so it can:

- map workflow steps to `inlineStep`, `focusedActiveStep`, or `confirmationStep`
- map results to `inlineStep`, `outcomeCard`, or `exceptionCard`
- derive compact detail fields from known payloads like:
  - `query`, `results`
  - `url`, `title`, `extractMode`
  - `title`, `dueAt`, `startAt`, `endAt`, `launchMode`

Do not hardcode giant keyword tables; use a small family-based classifier plus failure heuristics.

- [ ] **Step 4: Add any minimal payload metadata to block builder**

If mapper input needs more context, update `ChatBlockBuilder` payload shape minimally and keep backward compatibility with existing widget tests.

- [ ] **Step 5: Re-run the mapper and block-builder tests**

Run:

```bash
fvm flutter test test/services/tool_card_presentation_mapper_test.dart
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the mapper**

```bash
git add \
  lib/services/tool_card_presentation_mapper.dart \
  lib/tools/core/tool_display_names.dart \
  lib/services/chat_block_builder.dart \
  test/services/tool_card_presentation_mapper_test.dart \
  test/services/chat_block_builder_test.dart
git commit -m "feat: map tool events to semantic card variants"
```

---

## Task 3: Add Inline, Outcome, and Exception Widgets

**Files:**
- Create: `lib/widgets/chat_blocks/tool_inline_step_row.dart`
- Create: `lib/widgets/chat_blocks/tool_outcome_card.dart`
- Create: `lib/widgets/chat_blocks/tool_exception_card.dart`
- Modify: `lib/theme/app_theme_spec.dart`
- Modify: `lib/widgets/chat_blocks/tool_result_summary_row.dart`
- Test: `test/widgets/chat_blocks/tool_inline_step_row_test.dart`
- Test: `test/widgets/chat_blocks/tool_outcome_card_test.dart`
- Test: `test/widgets/chat_blocks/tool_exception_card_test.dart`

- [ ] **Step 1: Write failing widget tests for the new cards**

Add tests that assert:

- inline rows stay compact and show a single summary line
- outcome cards expose structured fields like title/time/location
- exception cards show reason and next-step guidance text

Example:

```dart
testWidgets('outcome card shows reminder title and due time', (tester) async {
  await tester.pumpWidget(
    buildTestApp(
      child: ToolOutcomeCard(
        model: ToolCardPresentationModel(
          variant: ToolCardPresentationVariant.outcomeCard,
          title: '已发起提醒创建',
          summary: '设计评审',
          primaryFields: const {'时间': '明天 09:00'},
        ),
      ),
    ),
  );

  expect(find.text('已发起提醒创建'), findsOneWidget);
  expect(find.text('明天 09:00'), findsOneWidget);
});
```

- [ ] **Step 2: Run the new widget tests and confirm they fail**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/tool_inline_step_row_test.dart
fvm flutter test test/widgets/chat_blocks/tool_outcome_card_test.dart
fvm flutter test test/widgets/chat_blocks/tool_exception_card_test.dart
```

Expected: FAIL because the widgets do not exist yet.

- [ ] **Step 3: Implement the widgets and any required theme tokens**

Add:

- compact low-noise inline row
- stronger but still restrained outcome card
- exception card with readable explanation and fallback emphasis

Any new colors added to `AppThemeSpec` must stay aligned with the existing calm palette.

- [ ] **Step 4: Turn the old result-summary widget into a compatibility wrapper**

Refactor `ToolResultSummaryRow` to either:

- delegate to the new variant widgets based on the semantic mapper, or
- become the inline-only compatibility path and move richer results elsewhere

Pick the smaller change that keeps tests readable.

- [ ] **Step 5: Re-run the widget tests**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/tool_inline_step_row_test.dart
fvm flutter test test/widgets/chat_blocks/tool_outcome_card_test.dart
fvm flutter test test/widgets/chat_blocks/tool_exception_card_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the result widget layer**

```bash
git add \
  lib/widgets/chat_blocks/tool_inline_step_row.dart \
  lib/widgets/chat_blocks/tool_outcome_card.dart \
  lib/widgets/chat_blocks/tool_exception_card.dart \
  lib/theme/app_theme_spec.dart \
  lib/widgets/chat_blocks/tool_result_summary_row.dart \
  test/widgets/chat_blocks/tool_inline_step_row_test.dart \
  test/widgets/chat_blocks/tool_outcome_card_test.dart \
  test/widgets/chat_blocks/tool_exception_card_test.dart
git commit -m "feat: add semantic tool result cards"
```

---

## Task 4: Refine Workflow Card Emphasis Rules

**Files:**
- Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
- Modify: `lib/models/chat/tool_workflow_step.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: Add failing tests for emphasis behavior**

Add tests that verify:

- only the current running step is expanded by default
- completed `web_search` and `Read` steps collapse into compact rows
- awaiting-confirmation `create_reminder` keeps its expanded action area
- only one workflow step is visually treated as the active focus

- [ ] **Step 2: Run the workflow rendering tests**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: FAIL because the current card does not expose the new emphasis tiers.

- [ ] **Step 3: Implement workflow emphasis tiers**

Update `ToolWorkflowCard` so it supports:

- inline history rows
- focused active step styling
- confirmation-step styling with action area

Keep the component calm and document-first; do not turn all steps into large panels.

- [ ] **Step 4: Re-run the workflow rendering tests**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the workflow-card refinement**

```bash
git add \
  lib/widgets/chat_blocks/tool_workflow_card.dart \
  lib/models/chat/tool_workflow_step.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart \
  test/widgets/chat_message_list_test.dart
git commit -m "feat: refine tool workflow emphasis states"
```

---

## Task 5: Route Chat Message Rendering Through Semantic Variants

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_blocks/tool_result_summary_row.dart`
- Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: Add end-to-end rendering tests**

Add widget tests for these scenarios:

- tool result for `search_chat_history` renders as compact inline row
- tool result for `create_reminder` renders as outcome card
- actionable failure renders as exception card
- workflow card still renders for running/confirmation states

- [ ] **Step 2: Run the message-list tests and confirm failure**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: FAIL because `chat_message_list.dart` still routes directly by block type.

- [ ] **Step 3: Implement semantic routing in message rendering**

In `chat_message_list.dart`:

- keep current block-type entry points
- for tool blocks, derive a `ToolCardPresentationModel`
- route to inline row, outcome card, exception card, or workflow card based on the variant

Avoid duplicating the mapper logic in the widget tree.

- [ ] **Step 4: Re-run the message-list tests**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the render routing**

```bash
git add \
  lib/widgets/chat_message_list.dart \
  lib/widgets/chat_blocks/tool_result_summary_row.dart \
  lib/widgets/chat_blocks/tool_workflow_card.dart \
  test/widgets/chat_message_list_test.dart
git commit -m "feat: route tool blocks through semantic variants"
```

---

## Task 6: Upgrade AskUserQuestion to a Workflow-Style Interaction Card

**Files:**
- Modify: `lib/widgets/interaction/ask_user_question_card.dart`
- Modify: `lib/theme/app_theme_spec.dart`
- Test: `test/widgets/interaction/ask_user_question_card_test.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: Write failing interaction-card tests**

Cover:

- card shows progress like `问题 1 / 2`
- current question feels like a workflow node instead of default checkbox tiles
- submit action communicates that the current turn will continue
- submitted-result state leaves a compact answered summary

- [ ] **Step 2: Run the interaction-card tests**

Run:

```bash
fvm flutter test test/widgets/interaction/ask_user_question_card_test.dart
```

Expected: FAIL because the current widget is still generic form UI.

- [ ] **Step 3: Refactor the card to share the workflow language**

Refactor `AskUserQuestionCard` to use:

- calmer structured header
- progress/status copy
- option chips or list rows that match the workflow system
- stronger submit affordance

Do not change the submission coordinator behavior in this task; keep the scope UI-only unless the tests prove a gap.

- [ ] **Step 4: Re-run the interaction-card tests**

Run:

```bash
fvm flutter test test/widgets/interaction/ask_user_question_card_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the interaction-card refresh**

```bash
git add \
  lib/widgets/interaction/ask_user_question_card.dart \
  lib/theme/app_theme_spec.dart \
  test/widgets/interaction/ask_user_question_card_test.dart \
  test/widgets/chat_message_list_test.dart
git commit -m "feat: refresh ask user question interaction card"
```

---

## Task 7: Verify, Document, and Polish

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-04-17-tool-use-card-semantics-design.md`

- [ ] **Step 1: Run targeted UI and service tests**

Run:

```bash
fvm flutter test \
  test/services/tool_card_presentation_mapper_test.dart \
  test/services/chat_block_builder_test.dart \
  test/widgets/chat_blocks/tool_inline_step_row_test.dart \
  test/widgets/chat_blocks/tool_outcome_card_test.dart \
  test/widgets/chat_blocks/tool_exception_card_test.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart \
  test/widgets/chat_message_list_test.dart \
  test/widgets/interaction/ask_user_question_card_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run:

```bash
fvm flutter analyze
```

Expected: PASS with no new errors.

- [ ] **Step 3: Update docs**

Update:

- `README.md` to reflect semantics-driven tool card rendering
- `AGENTS.md` if implementation constraints or architectural expectations changed
- the design spec if any field/variant names changed during implementation

- [ ] **Step 4: Perform manual verification**

Exercise at least these scenarios:

- web search followed by final answer
- fetch webpage followed by final answer
- create reminder success
- create reminder fallback
- AskUserQuestion multi-step submission

Preferred command for web smoke testing:

```bash
fvm flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 7357
```

Use `http://127.0.0.1:7357`.

- [ ] **Step 5: Commit docs and final polish**

```bash
git add README.md AGENTS.md docs/superpowers/specs/2026-04-17-tool-use-card-semantics-design.md
git commit -m "docs: document semantic tool card system"
```

---

## Notes For Execution

- Prefer shipping Tasks 1-3 first to establish the semantic layer and result widgets before changing the workflow card.
- Keep mapper logic centralized in `tool_card_presentation_mapper.dart`; do not duplicate classification rules in widgets.
- Preserve current persisted message payload compatibility wherever possible.
- If a task reveals a missing payload field needed for outcome cards, add the smallest compatible metadata surface rather than redesigning tool payload schemas.
- For failures, only promote to `exceptionCard` when the user needs to understand or act on the problem. Internal non-blocking failures should stay compact.

## Review Gap

This plan was written from the approved spec, but I did not dispatch the plan-document-reviewer subagent because subagent delegation in this session requires an explicit user request. If you want, I can still review the plan inline before execution.
