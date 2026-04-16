# Native Planner Tool Loop 重构实施计划

> **给执行型 agent 的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐项执行本计划。任务步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 删除 legacy JSON planner 和 `PlannerPromptBuilder`，让 provider-native `planTurnDecision()` 成为唯一 planner 入口，并让单次模型决策同时承载可见 assistant 文本与 tool calls。

**架构：** 保留现有 tool registry、step ledger 和 final answer pipeline，但将 planner loop 重建在统一的 native decision 语义之上。provider adapter 负责解析 mixed output，`AgentPlannerService` 负责在不回退 legacy 的前提下裁剪结果，`TurnHarness` 则把 planner 文本视为中间 assistant 输出，而不是最终答案。

**技术栈：** Flutter 3.29.3（用户已确认可直接使用）、Dart、flutter_test、现有 OpenAI Chat Completions / Responses adapter、当前 agent turn loop 与 repositories。

---

## 文件地图

**Planner 核心**

- 修改：`lib/services/agent_planner_service.dart`
- 删除：`lib/services/planner_prompt_builder.dart`
- 修改：`lib/models/agent/model_turn_decision.dart`
- 修改：`lib/models/agent/planner_tool_option.dart`
- 删除：`lib/models/agent/planner_tool_choice.dart`

**LLM 接口与 provider adapter**

- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 修改：`lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`
- 修改：`lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart`

**Turn loop 运行时**

- 修改：`lib/services/turn_harness.dart`
- 修改：`lib/models/chat_event.dart`
- 修改：`lib/repositories/chat_event_repository.dart`
- 修改：`lib/services/transcript_builder_service.dart`

**Tool 元数据**

- 修改：`lib/models/tool/tool_definition.dart`

**测试**

- 删除：`test/services/planner_prompt_builder_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/services/planner_decision_regression_test.dart`
- 修改：`test/models/llm/configurable_http_llm_test.dart`
- 修改：`test/models/llm/openai_tool_loop_adapter_test.dart`
- 修改：`test/services/turn_harness_test.dart`
- 修改：`test/services/transcript_builder_service_test.dart`

**文档**

- 修改：`README.md`
- 修改：`AGENTS.md`

### 任务 1：删除 legacy planner 入口

**文件：**
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 删除：`lib/services/planner_prompt_builder.dart`
- 删除：`lib/models/agent/planner_tool_choice.dart`
- 删除：`test/services/planner_prompt_builder_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`

- [ ] **步骤 1：先写失败测试**

```dart
test('当 native planner 返回 null 时，planNextDecision 返回 planner_request_failed', () async {
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

- [ ] **步骤 2：运行聚焦测试，确认当前仍依赖 legacy 代码**

运行：`flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`

预期：FAIL，因为当前测试仍引用 `planNextAction()`、`PlannerToolChoice` 或 `PlannerPromptBuilder`。

- [ ] **步骤 3：删除 legacy planner API**

从 `BaseLLM`、`ConfigurableHttpLLM` 和 `AgentPlannerService` 中删除 `planNextAction()`，并移除 legacy JSON 解析辅助逻辑与相关 import。

- [ ] **步骤 4：删除旧的 planner 专用类型与测试**

删除 `PlannerPromptBuilder`、`PlannerToolChoice` 以及对应测试。把调用点改为只消费 `ModelTurnDecision`。

- [ ] **步骤 5：重新运行聚焦测试**

运行：`flutter test test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart`

预期：仍可能 FAIL，但只会落在新的 native decision 语义缺口上，而不是 legacy 符号缺失。

- [ ] **步骤 6：提交**

```bash
git add lib/models/llm/base_llm.dart lib/services/agent_planner_service.dart lib/models/llm/configurable_http_llm.dart test/services/agent_planner_service_test.dart test/models/llm/configurable_http_llm_test.dart
git rm lib/services/planner_prompt_builder.dart lib/models/agent/planner_tool_choice.dart test/services/planner_prompt_builder_test.dart
git commit -m "refactor: remove legacy planner entry points"
```

### 任务 2：让 ToolDefinition 成为唯一工具描述来源

**文件：**
- 修改：`lib/models/tool/tool_definition.dart`
- 修改：`lib/models/agent/planner_tool_option.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`test/models/tool/tool_definition_test.dart`
- 修改：`test/services/planner_decision_regression_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`

- [ ] **步骤 1：先写失败测试**

```dart
test('planner tool option 只使用 ToolDefinition.descriptionForModel 作为工具描述', () async {
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

- [ ] **步骤 2：运行元数据测试**

运行：`flutter test test/models/tool/tool_definition_test.dart test/services/planner_decision_regression_test.dart test/services/agent_planner_service_test.dart`

预期：FAIL，因为当前 planner option 仍拼接了额外策略说明，或旧测试仍期待 prompt 内工具描述。

- [ ] **步骤 3：精简 planner-facing tool metadata**

保留 `ToolDefinition.descriptionForModel` 作为唯一语义描述来源。若执行策略仍需暴露，要么保留为独立字段，要么在唯一生成点里附加简短后缀。

- [ ] **步骤 4：删除 system prompt 中的工具定义渲染**

`AgentPlannerService` 只发送最小 planner 规则与 transcript/ledger 上下文，不再在 `availableTools` 之外枚举工具定义。

- [ ] **步骤 5：重新运行元数据测试**

运行：`flutter test test/models/tool/tool_definition_test.dart test/services/planner_decision_regression_test.dart test/services/agent_planner_service_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/models/tool/tool_definition.dart lib/models/agent/planner_tool_option.dart lib/services/agent_planner_service.dart test/models/tool/tool_definition_test.dart test/services/planner_decision_regression_test.dart test/services/agent_planner_service_test.dart
git commit -m "refactor: single-source planner tool descriptions"
```

### 任务 3：重定义 ModelTurnDecision 的 mixed output 语义

**文件：**
- 修改：`lib/models/agent/model_turn_decision.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/services/planner_decision_regression_test.dart`

- [ ] **步骤 1：先写失败测试**

```dart
test('过滤重复工具调用时会保留 assistant 文本', () {
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

- [ ] **步骤 2：运行 decision 测试**

运行：`flutter test test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart`

预期：FAIL，因为当前 sanitize 逻辑仍会把 mixed output 压回 terminal fallback。

- [ ] **步骤 3：更新 decision 语义**

在 `ModelTurnDecision` 的注释和构造点中明确：

- assistant 文本可以是中间态输出
- tool calls 与 assistant 文本可以共存
- terminal 仅表示“不再继续 planner loop”

- [ ] **步骤 4：调整 sanitize 逻辑**

过滤重复或不支持的工具调用时，保留 assistant 文本与 provider state。只有在 decision 已经没有任何可用输出时，才合成 terminal fallback 文本。

- [ ] **步骤 5：重新运行 decision 测试**

运行：`flutter test test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/models/agent/model_turn_decision.dart lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart
git commit -m "refactor: support mixed native planner decisions"
```

### 任务 4：让 provider adapter 正确解析 mixed output

**文件：**
- 修改：`lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`
- 修改：`lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 修改：`test/models/llm/openai_tool_loop_adapter_test.dart`
- 修改：`test/models/llm/configurable_http_llm_test.dart`

- [ ] **步骤 1：先写 mixed output 的失败测试**

```dart
test('chat completions parser 在有 tool_calls 时仍保留 assistant 文本', () {
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

- [ ] **步骤 2：运行 adapter 聚焦测试**

运行：`flutter test test/models/llm/openai_tool_loop_adapter_test.dart test/models/llm/configurable_http_llm_test.dart`

预期：FAIL，因为当前 adapter 在存在 tool call 时会丢掉 assistant 文本。

- [ ] **步骤 3：更新两个 adapter**

分别解析 assistant 文本与 tool calls，再组合成一个 `ModelTurnDecision` 返回，并继续保留 `response_id`、`call_id` 等 continuation 信息。

- [ ] **步骤 4：清理残余的 PlannerToolChoice 解析逻辑**

把 `ConfigurableHttpLLM` 中旧的结构化 choice 解析代码一并移除，只保留 `ModelTurnDecision` 路径。

- [ ] **步骤 5：重新运行 adapter 聚焦测试**

运行：`flutter test test/models/llm/openai_tool_loop_adapter_test.dart test/models/llm/configurable_http_llm_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart lib/models/llm/configurable_http_llm.dart test/models/llm/openai_tool_loop_adapter_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: parse mixed native planner outputs"
```

### 任务 5：让 TurnHarness 展示中间 planner 文本

**文件：**
- 修改：`lib/services/turn_harness.dart`
- 修改：`lib/models/chat_event.dart`
- 修改：`lib/repositories/chat_event_repository.dart`
- 修改：`test/services/turn_harness_test.dart`
- 修改：`test/repositories/chat_event_repository_test.dart`
- 修改：`test/models/chat_event_test.dart`

- [ ] **步骤 1：先写 turn loop 的失败测试**

```dart
test('turn harness 会先追加中间 assistant 文本，再执行工具调用', () async {
  final events = await harness.runTurn(turnId: 1, config: _config()).toList();

  expect(
    events.any((event) => event.content == '我先查一下，再给你结论'),
    isTrue,
  );
  expect(fakeToolExecutor.executedToolNames, ['web_search']);
});
```

- [ ] **步骤 2：运行 turn loop 测试**

运行：`flutter test test/services/turn_harness_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart`

预期：FAIL，因为当前 harness 要么把 assistant 文本当成终态，要么在有 tool calls 时忽略它。

- [ ] **步骤 3：增加明确的中间 assistant 事件形态**

通过新的 `ChatEventType` 或稳定的 payload 标记，把 planner/intermediate assistant 输出与 final answer assistant 输出区分开来。

- [ ] **步骤 4：更新 TurnHarness 执行顺序**

先持久化 provider state，再追加中间 assistant 文本，然后执行工具批次。只有当当前 decision 无待执行工具且进入终态时，才进入 final answer 生成。

- [ ] **步骤 5：重新运行 turn loop 测试**

运行：`flutter test test/services/turn_harness_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/services/turn_harness.dart lib/models/chat_event.dart lib/repositories/chat_event_repository.dart test/services/turn_harness_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart
git commit -m "feat: surface intermediate planner assistant messages"
```

### 任务 6：让 transcript 与 final answer 构建保持一致

**文件：**
- 修改：`lib/services/transcript_builder_service.dart`
- 修改：`test/services/transcript_builder_service_test.dart`
- 修改：`test/services/turn_harness_test.dart`

- [ ] **步骤 1：先写 transcript 的失败测试**

```dart
test('final answer transcript 会按顺序包含中间 planner assistant 文本', () async {
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

- [ ] **步骤 2：运行 transcript 测试**

运行：`flutter test test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart`

预期：FAIL，如果中间 planner 消息被过滤掉或顺序错误。

- [ ] **步骤 3：更新 transcript builder 规则**

确保中间 assistant 事件能进入 planner/final-answer transcript 构建，但不会被误判为 terminal output 标记。

- [ ] **步骤 4：重新运行 transcript 测试**

运行：`flutter test test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart`

预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add lib/services/transcript_builder_service.dart test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart
git commit -m "fix: align transcripts with intermediate planner messages"
```

### 任务 7：做完整的 planner/tool-loop 验证

**文件：**
- 视情况修改：前 1 到 6 任务中涉及的所有文件

- [ ] **步骤 1：运行完整的聚焦测试集**

运行：`flutter test test/services/agent_planner_service_test.dart test/services/planner_decision_regression_test.dart test/models/llm/configurable_http_llm_test.dart test/models/llm/openai_tool_loop_adapter_test.dart test/services/turn_harness_test.dart test/services/transcript_builder_service_test.dart test/repositories/chat_event_repository_test.dart test/models/chat_event_test.dart test/models/tool/tool_definition_test.dart`

预期：PASS。

- [ ] **步骤 2：对相关代码跑 analyze**

运行：`flutter analyze`

预期：PASS，planner、adapter、turn loop 相关代码没有新增问题。

- [ ] **步骤 3：如果有失败，先修最小闭环**

不要把无关问题一起混修。先重跑单个失败文件，再回到完整聚焦测试集。

- [ ] **步骤 4：提交验证修复**

```bash
git add lib test
git commit -m "test: stabilize native planner tool loop"
```

### 任务 8：更新项目文档

**文件：**
- 修改：`README.md`
- 修改：`AGENTS.md`

- [ ] **步骤 1：先列出需要覆盖的文档变更点**

包括：

- 不再存在 legacy JSON planner
- `descriptionForModel` 是唯一工具描述来源
- 单个 native decision 可以同时包含 assistant 文本与 tool calls
- turn loop 新增中间 assistant 消息语义

- [ ] **步骤 2：更新 `README.md`**

说明新的 planner/tool-loop 架构，并移除对 legacy planner 兼容路径的描述。

- [ ] **步骤 3：更新 `AGENTS.md`**

更新架构和实现约束，避免未来再次引入 `PlannerPromptBuilder` 式的重复描述，或重新把“tool vs text”压回互斥关系。

- [ ] **步骤 4：核对文档并提交**

运行：`git diff -- README.md AGENTS.md docs/superpowers/specs/2026-04-16-native-planner-tool-loop-redesign-design.md`

预期：只包含预期内的文档变更。

```bash
git add README.md AGENTS.md
git commit -m "docs: document native planner tool loop redesign"
```
