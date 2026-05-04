# ToolResult 单一结果源与上下文投影收口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 tool result 收口到 `summary + data` 单一 contract，删除 `uiSummaryText`、`contextText`、`toolResultText` 与 `additionalContextMessages`，并把 planner 回放统一改成基于 `data` 的上下文投影。

**Architecture:** 以 append-only transcript payload 为唯一 tool result 语义来源。`ToolResult` 只保留展示摘要与结构化结果真相；tool handler 不再平行返回额外 context message，也不再手写 planner-facing 文本。planner、Session Context、timeline、tool cards 统一消费这套 contract，其中 planner 可见 tool result 语义由专门的上下文投影层基于 `toolName + status + data + errorMessage` 生成。

**Tech Stack:** Flutter, Dart, flutter_test, Riverpod, SQLite transcript/ledger repositories, project architecture docs under `docs/architecture/`

---

## File Map

### Core model and orchestration

- Modify: `lib/models/tool/tool_result.dart`
- Modify: `lib/services/tool_call_service.dart`
- Modify: `lib/services/tool_orchestrator_service.dart`
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/repositories/chat_event_repository.dart`

### Context projection and planner-adjacent behavior

- Modify: `lib/services/session_context_projector.dart`
- Create or Modify: `lib/services/tool_result_context_projector.dart`
- Modify: `lib/services/agent_planner_service.dart`

### Tool handlers and adapters

- Modify: `lib/services/default_tool_adapters.dart`
- Modify any concrete handler/adapters still constructing `ToolResult`

### UI and presentation projections

- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Modify: `lib/services/tool_presentation_block_projector.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify tool result/timeline widgets and renderers that still read `uiSummaryText`

### Tests

- Modify: `test/models/tool/tool_invocation_test.dart`
- Modify: `test/services/session_context_projector_test.dart`
- Modify: `test/services/tool_orchestrator_service_test.dart`
- Modify: `test/services/turn_harness_test.dart`
- Modify: `test/services/default_tool_adapters_test.dart`
- Modify: `test/widgets/chat_timeline_row_test.dart`
- Modify widget/tool renderer tests that assert `uiSummaryText`

### Docs

- Modify: `docs/architecture/append-only-transcript.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `README.md` if tool-result/session-context wording is now inaccurate
- Reference: `docs/superpowers/specs/2026-05-04-tool-result-single-source-context-design.md`

## Task 1: Lock The New Contract In Tests

**Files:**
- Modify: `test/models/tool/tool_invocation_test.dart`
- Modify: `test/services/session_context_projector_test.dart`
- Modify: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write failing model-contract tests for the new ToolResult fields**

Add focused tests that assert:

```dart
test('serializes summary and data without uiSummaryText/contextText', () {
  const result = ToolResult(
    toolName: 'web_search',
    status: ToolExecutionStatus.success,
    summary: '已执行联网搜索',
    data: {'query': 'OpenAI latest docs'},
  );

  final json = result.toJson();

  expect(json['summary'], '已执行联网搜索');
  expect(json['data'], {'query': 'OpenAI latest docs'});
  expect(json.containsKey('uiSummaryText'), isFalse);
  expect(json.containsKey('contextText'), isFalse);
  expect(json.containsKey('toolResultText'), isFalse);
});
```

- [ ] **Step 2: Run focused model-contract tests to verify they fail**

Run: `fvm flutter test test/models/tool/tool_invocation_test.dart`

Expected: FAIL because `ToolResult` still exposes `uiSummaryText/contextText` or old fallback helpers.

- [ ] **Step 3: Write failing projector/orchestrator tests for data-driven transcript context**

Add tests that assert:

- `SessionContextProjector` 不再读取 `summary`
- planner-visible tool result 文本来自 `ToolResult.data`
- no test uses or expects `contextText` / `toolResultText`
- `ToolOrchestratorService` preserves `summary` and `data` when attaching tool access

Example assertion:

```dart
expect(
  message?.text,
  contains('OpenAI latest docs'),
);
```

- [ ] **Step 4: Run focused projector/orchestrator tests to verify they fail**

Run: `fvm flutter test test/services/session_context_projector_test.dart test/services/tool_orchestrator_service_test.dart`

Expected: FAIL because production code still uses `contextText/resolvedContextText` or summary fallback, and still exposes `additionalContextMessages`.

- [ ] **Step 5: Commit the red tests**

```bash
git add test/models/tool/tool_invocation_test.dart test/services/session_context_projector_test.dart test/services/tool_orchestrator_service_test.dart
git commit -m "test: lock tool result single-source contract"
```

## Task 2: Refactor ToolResult To The Target Model

**Files:**
- Modify: `lib/models/tool/tool_result.dart`
- Test: `test/models/tool/tool_invocation_test.dart`

- [ ] **Step 1: Replace the old ToolResult fields in the model**

Implement the target shape:

- keep `summary`
- delete `uiSummaryText`
- delete `contextText`
- delete `toolResultText`
- remove any planner-text helper aliases
- update comments to explicitly declare `summary` as display-only and `data` as the semantic result truth
- add a short doc reference to `docs/architecture/session-context-management.md`

- [ ] **Step 2: Remove obsolete resolution helpers**

Delete:

- `resolvedContextText`
- any legacy fallback chain that references `contextText`
- any helper that allows planner semantics to fall back to `summary`

- [ ] **Step 3: Update serialization and deserialization**

Ensure `toJson()` / `fromJson()` only read/write:

- `summary`
- `data`
- existing policy/access/error fields

Do not keep backward-compatibility reads for `uiSummaryText/contextText/toolResultText` unless absolutely required for a currently-persisted runtime path. Given the repo guidance, prefer direct refactor.

- [ ] **Step 4: Run focused model tests**

Run: `fvm flutter test test/models/tool/tool_invocation_test.dart`

Expected: PASS

- [ ] **Step 5: Commit the ToolResult model refactor**

```bash
git add lib/models/tool/tool_result.dart test/models/tool/tool_invocation_test.dart
git commit -m "refactor: simplify tool result contract"
```

## Task 3: Remove additionalContextMessages From The Runtime Path

**Files:**
- Modify: `lib/services/tool_call_service.dart`
- Modify: `lib/services/tool_orchestrator_service.dart`
- Modify: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write or update failing tests that forbid additionalContextMessages**

Add assertions such as:

```dart
expect(
  result,
  isA<ToolPreparationResult>().having(
    (value) => value.toolResult?.data,
    'data',
    containsPair('query', 'OpenAI latest docs'),
  ),
);
```

And remove assertions that inspect `result.additionalContextMessages`.

- [ ] **Step 2: Run the orchestrator tests to verify they fail**

Run: `fvm flutter test test/services/tool_orchestrator_service_test.dart`

Expected: FAIL because `ToolPreparationResult` still has `additionalContextMessages`.

- [ ] **Step 3: Remove the field from ToolPreparationResult**

Delete:

- `additionalContextMessages` field
- constructor parameter
- `.noTool()` default entry
- any comments describing it as a future adapter channel

- [ ] **Step 4: Remove buildContextMessages usage from the orchestration path**

In `ToolOrchestratorService`:

- stop calling `runtimeHandler.buildContextMessages(...)` for planner/runtime flow
- remove trace data related only to context message length
- preserve all other execution tracing

Do not invent a replacement side-channel.

- [ ] **Step 5: Preserve ToolResult semantic payload when attaching tool access**

Fix `_attachToolAccess()` to copy forward:

- `summary`
- `data`
- `errorMessage`
- `executionPolicy`
- `toolAccess`

- [ ] **Step 6: Run focused orchestrator tests**

Run: `fvm flutter test test/services/tool_orchestrator_service_test.dart`

Expected: PASS

- [ ] **Step 7: Commit the runtime-path cleanup**

```bash
git add lib/services/tool_call_service.dart lib/services/tool_orchestrator_service.dart test/services/tool_orchestrator_service_test.dart
git commit -m "refactor: remove extra tool context message channel"
```

## Task 4: Convert Transcript Append And Session Projection

**Files:**
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/repositories/chat_event_repository.dart`
- Modify: `lib/services/session_context_projector.dart`
- Create or Modify: `lib/services/tool_result_context_projector.dart`
- Test: `test/services/session_context_projector_test.dart`

- [ ] **Step 1: Write failing tests that lock transcript payload and projection behavior**

Add tests covering:

- transcript `content` stores `summary`
- transcript `payloadJson` stores full `ToolResult`
- projector no longer reads `summary` for planner semantics
- projector builds planner-visible text from `data`
- no path falls back from missing structured result to `summary`

Include a concrete `web_search` example:

```dart
final payload = ToolResult(
  toolName: 'web_search',
  status: ToolExecutionStatus.success,
  summary: '已执行联网搜索',
  data: {
    'query': 'OpenAI latest docs',
    'results': [
      {'title': 'OpenAI docs', 'url': 'https://platform.openai.com'}
    ],
  },
);

expect(projected.text, contains('OpenAI docs'));
expect(projected.text, contains('https://platform.openai.com'));
expect(projected.text, isNot(contains('已执行联网搜索')));
```

- [ ] **Step 2: Update transcript append to store summary plus full payload**

In:

- `DecisionToolCallExecutor`
- `TurnHarness`

ensure:

- `appendToolResult(content: toolResult.summary, payloadJson: toolResult.toJson())`
- `appendToolError(content: toolResult.summary, payloadJson: toolResult.toJson())`

- [ ] **Step 3: Add or extract a dedicated ToolResult context projector**

Implement one narrow component responsible for:

- taking `ToolResult`
- producing planner-visible context text
- centralizing tool-specific formatting rules
- using `data` as the primary semantic source
- never reading `summary`

Suggested API:

```dart
class ToolResultContextProjector {
  String? projectToContextText(ToolResult result);
}
```

- [ ] **Step 4: Wire SessionContextProjector to the new result projector**

Replace any logic equivalent to:

```dart
toolResult.summary
```

with:

```dart
final result = ToolResult.fromJson(payload);
final text = toolResultContextProjector.projectToContextText(result);
```

If `text` is empty, return `null` or a structured minimal failure fact based on `toolName/status/errorMessage`; do not fall back to `summary`.

- [ ] **Step 5: Run focused projector tests**

Run: `fvm flutter test test/services/session_context_projector_test.dart`

Expected: PASS

- [ ] **Step 6: Commit transcript projection updates**

```bash
git add lib/services/decision_tool_call_executor.dart lib/services/turn_harness.dart lib/repositories/chat_event_repository.dart lib/services/session_context_projector.dart lib/services/tool_result_context_projector.dart test/services/session_context_projector_test.dart
git commit -m "refactor: project tool results from structured data"
```

## Task 5: Update Tool Adapters And Concrete Tool Results

**Files:**
- Modify: `lib/services/default_tool_adapters.dart`
- Modify any concrete tool handlers constructing `ToolResult`
- Test: `test/services/default_tool_adapters_test.dart`

- [ ] **Step 1: Write failing adapter tests for the new ToolResult contract**

Update tests to assert:

- tool results return `summary`
- tools no longer return `uiSummaryText/contextText`
- `web_search` / `fetch_webpage` / action tools provide the structured result needed for later projection through `data`

- [ ] **Step 2: Update adapters to emit summary + data only**

For each touched tool:

- ensure `summary` remains compact
- remove `uiSummaryText/contextText`
- verify `data` contains enough facts for downstream context projection
- prefer adding small structured fields over embedding large free-form text blobs

`web_search` should preserve at least:

- `query`
- `provider`
- `results[].title`
- `results[].url`
- `results[].snippet`
- `results[].source`
- `results[].publishedDate`

- [ ] **Step 3: Run focused adapter tests**

Run: `fvm flutter test test/services/default_tool_adapters_test.dart`

Expected: PASS

- [ ] **Step 4: Commit adapter migration**

```bash
git add lib/services/default_tool_adapters.dart test/services/default_tool_adapters_test.dart
git commit -m "refactor: align tool adapters to summary and data"
```

## Task 6: Update UI Projection And Rendering

**Files:**
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Modify: `lib/services/tool_presentation_block_projector.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify related widget tests

- [ ] **Step 1: Write failing UI projection tests**

Assert that:

- result cards read `summary`
- timeline rows still show compact summary
- no renderer reads removed fields

- [ ] **Step 2: Update projection and renderer code**

Change all tool-result presentation paths to read:

- `ToolResult.summary`

while leaving planner-context projection fully separate.

- [ ] **Step 3: Run focused widget/UI tests**

Run: `fvm flutter test test/widgets/chat_timeline_row_test.dart test/widgets/chat_message_list_test.dart test/widgets/tool_renderers`

Expected: PASS

- [ ] **Step 4: Commit UI contract migration**

```bash
git add lib/controllers/agent_event_processor.dart lib/services/chat_block_builder.dart lib/services/tool_presentation_block_projector.dart lib/widgets/chat_timeline/chat_timeline_row.dart test/widgets/chat_timeline_row_test.dart test/widgets/chat_message_list_test.dart test/widgets/tool_renderers
git commit -m "refactor: align tool result ui with summary"
```

## Task 7: Update Architecture Docs And Anti-Drift References

**Files:**
- Modify: `docs/architecture/append-only-transcript.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `README.md` if needed
- Reference: `docs/superpowers/specs/2026-05-04-tool-result-single-source-context-design.md`

- [ ] **Step 1: Rewrite the tool-result contract section in session-context docs**

Replace old wording about:

- `uiSummaryText`
- `contextText`
- `toolResultText`

with the new `summary + data` contract and data-driven context projection rules.

- [ ] **Step 2: Strengthen append-only transcript constraints**

Add explicit language that:

- `additionalContextMessages` does not exist
- tool handlers must not add a parallel context channel
- transcript payload is the only tool-result semantic source for replay
- summary fallback into planner semantics is forbidden

- [ ] **Step 3: Add mutual references**

Ensure:

- spec references architecture docs
- architecture docs reference the spec or the relevant implementation rationale where appropriate
- code comments point back to architecture docs, not only local assumptions

- [ ] **Step 4: Update README if current wording is now stale**

If README describes tool/session context text fields inaccurately, correct it in the same change.

- [ ] **Step 5: Review docs for stale field names**

Run: `rg -n "uiSummaryText|contextText|toolResultText|additionalContextMessages" docs lib test -S`

Expected: no remaining active contract wording in current docs/code/tests except intentional historical references.

- [ ] **Step 6: Commit documentation cleanup**

```bash
git add docs/architecture/append-only-transcript.md docs/architecture/session-context-management.md README.md docs/superpowers/specs/2026-05-04-tool-result-single-source-context-design.md
git commit -m "docs: codify structured tool result context projection"
```

## Task 8: Run Verification Suites

- [ ] **Step 1: Run focused unit/widget suites**

Run:

```bash
fvm flutter test \
  test/services/session_context_projector_test.dart \
  test/services/tool_orchestrator_service_test.dart \
  test/services/default_tool_adapters_test.dart \
  test/widgets/chat_message_list_test.dart \
  test/widgets/chat_timeline_row_test.dart
```

Expected: PASS

- [ ] **Step 2: Run broader regression suites touching tool loop**

Run:

```bash
fvm flutter test \
  test/services/turn_harness_test.dart \
  test/services/decision_tool_call_executor_test.dart \
  test/providers/chat_controller_tool_flow_test.dart
```

Expected: PASS

- [ ] **Step 3: Run analyzer**

Run: `fvm flutter analyze`

Expected: PASS

## Task 9: Final Review And Handoff

- [ ] **Step 1: Spot-check architecture invariants in final code**

Verify checklist:

- no production code references `toolResultText`
- no runtime path uses `additionalContextMessages`
- no planner-context path reads `summary`
- UI only reads `summary`
- docs and code comments point to the same invariant

- [ ] **Step 2: Commit final cleanup**

```bash
git add lib test docs README.md
git commit -m "refactor: finalize tool result structured context flow"
```

## Plan Review Checklist

- [ ] Every `ToolResult` producer uses `summary` and `data`
- [ ] No runtime path still depends on `additionalContextMessages`
- [ ] Transcript `content` remains compact UI text
- [ ] Planner-visible context comes from transcript payload projection
- [ ] UI only displays `summary`
- [ ] Current architecture docs no longer describe `uiSummaryText/contextText` as active contract
- [ ] No stale comments or tests imply parallel context channels still exist
