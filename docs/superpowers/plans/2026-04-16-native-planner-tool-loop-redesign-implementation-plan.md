# Native Planner Tool Loop Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the legacy JSON planner and `PlannerPromptBuilder`, make provider-native `planTurnDecision()` the only planner entry, and let one model turn carry both visible assistant text and tool calls.

**Architecture:** Keep the existing tool registry, step ledger, and final-answer pipeline, but rebuild the planner loop around one native decision model. Provider adapters should parse mixed outputs, `AgentPlannerService` should sanitize without reintroducing fallback paths, and `TurnHarness` should treat planner text as intermediate assistant output instead of a final answer.

**Tech Stack:** Flutter 3.29.2 via `fvm flutter`, Dart, flutter_test, existing OpenAI Chat Completions / Responses adapters, current agent turn loop and repositories.

---

## File Map

**Planner core**

- Modify: `lib/services/agent_planner_service.dart`
- Delete: `lib/services/planner_prompt_builder.dart`
- Modify: `lib/models/agent/model_turn_decision.dart`
- Modify: `lib/models/agent/planner_tool_option.dart`
- Delete: `lib/models/agent/planner_tool_choice.dart`

**LLM interface and provider adapters**

- Modify: `lib/models/llm/base_llm.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`
- Modify: `lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart`

**Turn-loop runtime**

- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/repositories/chat_event_repository.dart`
- Modify: `lib/services/transcript_builder_service.dart`

**Tool metadata**

- Modify: `lib/models/tool/tool_definition.dart`

**Tests**

- Delete: `test/services/planner_prompt_builder_test.dart`
- Modify: `test/services/agent_planner_service_test.dart`
- Modify: `test/services/planner_decision_regression_test.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`
- Modify: `test/models/llm/openai_tool_loop_adapter_test.dart`
- Modify: `test/services/turn_harness_test.dart`
- Modify: `test/services/transcript_builder_service_test.dart`

**Docs**

- Modify: `README.md`
- Modify: `AGENTS.md`

### Task 1: Remove legacy planner entry points

**Files:**
- Modify: `lib/models/llm/base_llm.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Delete: `lib/services/planner_prompt_builder.dart`
- Delete: `lib/models/agent/planner_tool_choice.dart`
- Delete: `test/services/planner_prompt_builder_test.dart`
- Modify: `test/services/agent_planner_service_test.dart`

- [ ] **Step 1: Write the failing cleanup tests**

```dart
test('planNextDecision returns planner_request_failed when native planner returns null', () async {
  final decision = await service.planNextDecision(
    turn: _turn(),
    transcript: [_userEvent()],
    steps: const [],
    config: ChatConfig(useReasoning: false, systemPrompt: ''),
    limits: const AgentLoopLimits(),
  );

  expect(decision!.diagnosticCode, 'planner_request_failed');
});
```

- [ ] **Step 2: Run the focused tests and confirm they still depend on legacy code**

Run: `fvm flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`

Expected: FAIL because the suite still references `planNextAction()`, `PlannerToolChoice`, or `PlannerPromptBuilder`.

- [ ] **Step 3: Remove legacy planner APIs**

Delete `planNextAction()` from `BaseLLM`, `ConfigurableHttpLLM`, and `AgentPlannerService`, along with legacy JSON parsing helpers and imports.

- [ ] **Step 4: Remove old planner-only types and tests**

Delete `PlannerPromptBuilder`, `PlannerToolChoice`, and their dedicated tests. Update any callers to consume only `ModelTurnDecision`.

- [ ] **Step 5: Re-run the focused tests**

Run: `fvm flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`

Expected: FAIL only on the next native-decision semantic gaps, not on missing legacy symbols.

- [ ] **Step 6: Commit**

```bash
git add lib/models/llm/base_llm.dart lib/services/agent_planner_service.dart lib/models/llm/configurable_http_llm.dart test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart
git rm lib/services/planner_prompt_builder.dart lib/models/agent/planner_tool_choice.dart test/services/planner_prompt_builder_test.dart
git commit -m "refactor: remove legacy planner entry points"
```

### Task 2: Make tool descriptions single-sourced from ToolDefinition

**Files:**
- Modify: `lib/models/tool/tool_definition.dart`
- Modify: `lib/models/agent/planner_tool_option.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `test/models/tool/tool_definition_test.dart`
- Modify: `test/services/planner_decision_regression_test.dart`
- Modify: `test/services/agent_planner_service_test.dart`

- [ ] **Step 1: Write the failing metadata tests**

```dart
test('planner tool option uses ToolDefinition.descriptionForModel as the only tool description source', () async {
  await service.planNextDecision(
    turn: _turn('请读取 https://example.com'),
    transcript: [_userEvent('请读取 https://example.com')],
    steps: const [],
    config: ChatConfig(useReasoning: false, systemPrompt: ''),
    limits: const AgentLoopLimits(),
  );

  expect(llm.lastToolOptions!.single.description, '当用户已经提供 URL 时使用。');
});
```

- [ ] **Step 2: Run metadata-focused tests**

Run: `fvm flutter test test/models/tool/tool_definition_test.dart test/services/planner_decision_regression_test.dart test/services/agent_planner_service_test.dart`

Expected: FAIL because planner options still append extra policy prose or tests still expect prompt-expanded tool descriptions.

- [ ] **Step 3: Simplify planner-facing tool metadata**

Keep `ToolDefinition.descriptionForModel` as the sole semantic description. If execution policy must remain visible, represent it as a separate field or a tightly controlled derived suffix in one place only.

- [ ] **Step 4: Remove tool-definition rendering from system prompt construction**

`AgentPlannerService` should send only minimal planner rules plus transcript/ledger context; it must stop enumerating tool definitions outside `availableTools`.

- [ ] **Step 5: Re-run metadata-focused tests**

Run: `fvm flutter test test/models/tool/tool_definition_test.dart test/services/planner_decision_regression_test.dart test/services/agent_planner_service_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/tool/tool_definition.dart lib/models/agent/planner_tool_option.dart lib/services/agent_planner_service.dart test/models/tool/tool_definition_test.dart test/services/planner_decision_regression_test.dart test/services/agent_planner_service_test.dart
git commit -m "refactor: single-source planner tool descriptions"
```

### Task 3: Redefine ModelTurnDecision for mixed outputs

**Files:**
- Modify: `lib/models/agent/model_turn_decision.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `test/services/agent_planner_service_test.dart`
- Modify: `test/services/planner_decision_regression_test.dart`

- [ ] **Step 1: Write the failing decision-semantics tests**

```dart
test('sanitizing duplicate tool calls preserves assistant text', () {
  final sanitized = service.debugSanitizeDecision(
    const ModelTurnDecision(
      toolCalls: [ModelToolCall(toolName: 'web_search', arguments: {'query': 'x'}, sequence: 0)],
      assistantMessage: '我先查一下',
      providerState: {},
      isTerminal: false,
    ),
    allowedToolNames: ['web_search'],
    steps: [_completedStep('web_search', {'query': 'x'})],
  );

  expect(sanitized.assistantMessage, '我先查一下');
});
```

- [ ] **Step 2: Run the decision tests**

Run: `fvm flutter test test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart`

Expected: FAIL because current sanitization still collapses mixed output into terminal fallback behavior.

- [ ] **Step 3: Update decision semantics**

Clarify in `ModelTurnDecision` comments and construction sites that:

- assistant text is intermediate-capable
- tool calls and assistant text can coexist
- terminal status only means “no further planner loop required”

- [ ] **Step 4: Adjust sanitization**

When filtering duplicate or unsupported tool calls, preserve assistant text and provider state. Only synthesize fallback terminal text when the decision no longer has any useful output.

- [ ] **Step 5: Re-run the decision tests**

Run: `fvm flutter test test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/agent/model_turn_decision.dart lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart
git commit -m "refactor: support mixed native planner decisions"
```

### Task 4: Parse mixed assistant text and tool calls in provider adapters

**Files:**
- Modify: `lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`
- Modify: `lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `test/models/llm/openai_tool_loop_adapter_test.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: Add failing adapter tests for mixed outputs**

```dart
test('chat completions parser keeps assistant text when tool_calls are present', () {
  final decision = adapter.parseDecision({
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': '我先读取这个页面。',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'fetch_webpage',
                'arguments': '{"url":"https://example.com"}',
              },
            },
          ],
        },
      },
    ],
  });

  expect(decision!.assistantMessage, '我先读取这个页面。');
  expect(decision.toolCalls.single.toolName, 'fetch_webpage');
});
```

- [ ] **Step 2: Run adapter-focused tests**

Run: `fvm flutter test test/models/llm/openai_tool_loop_adapter_test.dart test/models/llm/configurable_http_llm_test.dart`

Expected: FAIL because adapters currently drop assistant text when tool calls exist.

- [ ] **Step 3: Update both adapters**

Parse assistant text and tool calls independently, then return one `ModelTurnDecision` containing both. Preserve `response_id` and call ids exactly as before.

- [ ] **Step 4: Remove any remaining `PlannerToolChoice` parsing code**

Trim `ConfigurableHttpLLM` down so planner parsing only feeds `ModelTurnDecision`.

- [ ] **Step 5: Re-run adapter-focused tests**

Run: `fvm flutter test test/models/llm/openai_tool_loop_adapter_test.dart test/models/llm/configurable_http_llm_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart lib/models/llm/configurable_http_llm.dart test/models/llm/openai_tool_loop_adapter_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: parse mixed native planner outputs"
```

### Task 5: Teach TurnHarness to display intermediate planner text

**Files:**
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/repositories/chat_event_repository.dart`
- Modify: `test/services/turn_harness_test.dart`
- Modify: `test/repositories/chat_event_repository_test.dart`
- Modify: `test/models/chat_event_test.dart`

- [ ] **Step 1: Add failing turn-loop tests**

```dart
test('turn harness appends intermediate assistant text before executing tool calls', () async {
  final events = await harness.runTurn(turnId: 1, config: _config()).toList();

  expect(
    events.any((event) => event.content == '我先查一下，再给你结论'),
    isTrue,
  );
  expect(fakeToolExecutor.executedToolNames, ['web_search']);
});
```

- [ ] **Step 2: Run turn-loop tests**

Run: `fvm flutter test test/services/turn_harness_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart`

Expected: FAIL because the harness currently treats assistant text as terminal or ignores it when tool calls exist.

- [ ] **Step 3: Add an explicit intermediate assistant event shape**

Use either a new `ChatEventType` or a stable payload marker so transcript consumers can distinguish planner/intermediate assistant output from final-answer assistant output.

- [ ] **Step 4: Update TurnHarness execution order**

Persist provider state, append intermediate assistant text, then execute tools. Only enter final answer generation when no tool calls remain and the decision is terminal.

- [ ] **Step 5: Re-run turn-loop tests**

Run: `fvm flutter test test/services/turn_harness_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/turn_harness.dart lib/models/chat_event.dart lib/repositories/chat_event_repository.dart test/services/turn_harness_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart
git commit -m "feat: surface intermediate planner assistant messages"
```

### Task 6: Keep transcript and final-answer building aligned

**Files:**
- Modify: `lib/services/transcript_builder_service.dart`
- Modify: `test/services/transcript_builder_service_test.dart`
- Modify: `test/services/turn_harness_test.dart`

- [ ] **Step 1: Add failing transcript tests**

```dart
test('final answer transcript includes intermediate planner assistant messages in order', () async {
  final messages = await service.buildFinalAnswerMessages(
    groupId: 1,
    turn: turn,
    transcript: [
      _userEvent('帮我查一下'),
      _intermediateAssistantEvent('我先查一下'),
      _toolResultEvent('搜索完成'),
    ],
    systemPrompt: '',
  );

  expect(messages.map((m) => m.text), containsAllInOrder(['帮我查一下', '我先查一下', '搜索完成']));
});
```

- [ ] **Step 2: Run transcript tests**

Run: `fvm flutter test test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart`

Expected: FAIL if intermediate planner messages are filtered out or misordered.

- [ ] **Step 3: Update transcript builder rules**

Ensure intermediate assistant events are included in planner/final-answer transcript construction without being mistaken for terminal output markers.

- [ ] **Step 4: Re-run transcript tests**

Run: `fvm flutter test test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/transcript_builder_service.dart test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart
git commit -m "fix: align transcripts with intermediate planner messages"
```

### Task 7: Run full planner/tool-loop verification

**Files:**
- Modify as needed: any files touched in Tasks 1-6

- [ ] **Step 1: Run the full targeted suite**

Run: `fvm flutter test test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart test/models/llm/configurable_http_llm_test.dart test/models/llm/openai_tool_loop_adapter_test.dart test/services/turn_harness_test.dart test/services/transcript_builder_service_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart test/models/tool/tool_definition_test.dart`

Expected: PASS.

- [ ] **Step 2: Run analyzer on touched planner/runtime code**

Run: `fvm flutter analyze`

Expected: PASS with no new issues in planner, adapter, or turn-loop code.

- [ ] **Step 3: If failures appear, fix the smallest failing slice first**

Do not batch unrelated fixes. Re-run only the failing test file, then re-run the full targeted suite.

- [ ] **Step 4: Commit verification fixes**

```bash
git add lib test
git commit -m "test: stabilize native planner tool loop"
```

### Task 8: Update project docs for the new planner model

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add failing doc checklist comments in the plan branch**

Record the doc deltas to cover:

- no more legacy JSON planner
- `descriptionForModel` as the single tool description source
- mixed assistant text + tool calls in one native decision
- intermediate assistant messages in the turn loop

- [ ] **Step 2: Update `README.md`**

Document the new planner/tool-loop architecture and remove references to legacy planner compatibility.

- [ ] **Step 3: Update `AGENTS.md`**

Refresh the architecture and implementation notes so future work does not reintroduce `PlannerPromptBuilder`-style duplication or “tool vs text” mutual exclusivity.

- [ ] **Step 4: Verify docs and commit**

Run: `git diff -- README.md AGENTS.md docs/superpowers/specs/2026-04-16-native-planner-tool-loop-redesign-design.md`

Expected: Only intentional documentation changes.

```bash
git add README.md AGENTS.md
git commit -m "docs: document native planner tool loop redesign"
```
