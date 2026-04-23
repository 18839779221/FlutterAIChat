# Tool Transcript 保真上下文实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 planner 与 final answer 在消费 current turn transcript 和 recent completed turns 时保留 tool use / tool result 的原始结构语义，不再把工具回执重新翻译成摘要式 assistant 历史文本，并为 `tool_result` 预留默认 passthrough 的可选转换口子。

**Architecture:** 在 `SessionContextProjector` 与上下文构建链路中新增结构化 context item 中间表示，明确区分普通消息、assistant tool use、user tool result。`tool_result` 在进入 context 前经过统一的 transformer contract，默认直接透传原始结果文本；当前轮与跨轮 recent history 共用同一套投影规则，避免 `Write` / `Edit` 成功回执污染后续 planner。

**Tech Stack:** Flutter 3.29.x、Dart、flutter_test、现有 `ChatEvent` / `SessionContextService` / `TranscriptBuilderService` / `BaseLLM` 上下文构建链路。

---

## 文件地图

**新增模型与接口**

- Create: `lib/models/context/model_context_item.dart`
- Create: `lib/models/context/tool_result_context_transformer.dart`

**核心投影与构建链路**

- Modify: `lib/services/session_context_projector.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/transcript_builder_service.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `lib/models/llm/base_llm.dart`（仅当 planner / final-answer 调用需要接收新的结构化输入模型）
- Modify: `lib/services/chat_service.dart`（仅当 final answer 构建链路需要统一消费新的 context item）

**工具定义层**

- Modify: `lib/models/tool/tool_result.dart`
- Modify: `lib/tools/core/tool_handler.dart`
- Modify: `lib/tools/handlers/write_tool_handler.dart`
- Modify: `lib/tools/handlers/edit_tool_handler.dart`

**测试**

- Modify: `test/services/session_context_projector_test.dart`
- Modify: `test/services/session_context_service_test.dart`
- Modify: `test/services/transcript_builder_service_test.dart`
- Modify: `test/services/turn_harness_test.dart`
- Modify: `test/tools/handlers/write_tool_handler_test.dart`
- Modify: `test/tools/handlers/edit_tool_handler_test.dart`

**文档**

- Reference: `docs/superpowers/specs/2026-04-24-tool-transcript-context-fidelity-design.md`

## 任务 1：定义结构化 context item 与 transformer contract

**Files:**
- Create: `lib/models/context/model_context_item.dart`
- Create: `lib/models/context/tool_result_context_transformer.dart`
- Modify: `lib/models/tool/tool_result.dart`

- [ ] **Step 1: 写失败测试前先阅读现有投影与工具结果 contract**

阅读：
- `lib/services/session_context_projector.dart`
- `lib/models/tool/tool_result.dart`
- `lib/services/session_context_service.dart`

目标：确认当前 `toolResult` 被压平为 assistant 文本的入口。

- [ ] **Step 2: 在 `test/services/session_context_projector_test.dart` 新增失败测试，锁定结构化语义**

示例测试内容：

```dart
test('projects successful Edit result as userToolResult instead of assistant text summary', () {
  final projector = SessionContextProjector();

  final item = projector.projectEventToContextItem(
    ChatEvent(
      turnId: 1,
      groupId: 1,
      sequence: 1,
      eventType: ChatEventType.toolResult,
      content: '已编辑文件：my_hobbies.md',
      payloadJson: const {
        'toolName': 'Edit',
        'status': 'success',
        'summary': '已编辑文件：my_hobbies.md',
        'toolResultText': 'Successfully edited my_hobbies.md',
        'data': {'filePath': 'my_hobbies.md'},
      },
    ),
  );

  expect(item, isNotNull);
  expect(item!.type, ModelContextItemType.userToolResult);
  expect(item.text, 'Successfully edited my_hobbies.md');
});
```

- [ ] **Step 3: 运行单测，确认新模型与接口尚不存在**

Run: `flutter test test/services/session_context_projector_test.dart`

Expected: FAIL，提示缺少 `ModelContextItem`、`projectEventToContextItem` 或 context type 定义。

- [ ] **Step 4: 定义 `ModelContextItem`**

在 `lib/models/context/model_context_item.dart` 中新增：

- `ModelContextItemType` 枚举
- `text`
- `toolName`
- `arguments`
- `timestamp`
- 必要的工厂方法，例如：
  - `systemMessage(...)`
  - `userMessage(...)`
  - `assistantMessage(...)`
  - `assistantToolUse(...)`
  - `userToolResult(...)`

注释中明确：
- 这是模型上下文中间表示
- 不是 UI message
- 不是数据库 schema

- [ ] **Step 5: 定义 `ToolResultContextTransformer` contract**

在 `lib/models/context/tool_result_context_transformer.dart` 中定义统一接口，建议形态：

```dart
typedef ToolResultContextTransformer = String Function(ToolResult result);
```

或小型 class/interface，只要满足：

- 默认可 passthrough
- 后续可按工具覆盖

- [ ] **Step 6: 在 `ToolResult` 或工具层补一个默认 context text 解析入口**

要求：

- 默认优先使用 `resolvedToolResultText`
- 若无，则退回 `summary`
- 保证默认行为不做转换

- [ ] **Step 7: 重新运行单测**

Run: `flutter test test/services/session_context_projector_test.dart`

Expected: 仍可能 FAIL，但失败点应从“模型不存在”推进到“投影逻辑尚未改造”。

- [ ] **Step 8: Commit**

```bash
git add lib/models/context/model_context_item.dart lib/models/context/tool_result_context_transformer.dart lib/models/tool/tool_result.dart test/services/session_context_projector_test.dart
git commit -m "feat: add structured model context items"
```

## 任务 2：改造 SessionContextProjector，保留 tool transcript 结构

**Files:**
- Modify: `lib/services/session_context_projector.dart`
- Modify: `test/services/session_context_projector_test.dart`

- [ ] **Step 1: 为 projector 增加新的结构化投影 API**

目标 API：

- `projectEventToContextItem(...)`
- `projectEventsToContextItems(...)`

保留旧 API 仅在必要时作为兼容层，但不要让它继续成为主入口。

- [ ] **Step 2: 写失败测试，覆盖三类关键映射**

需要至少覆盖：

- `assistantToolCall -> assistantToolUse`
- `toolResult -> userToolResult`
- `assistantPlannerMessage -> assistantMessage`

并断言：

- `Edit` / `Write` 成功结果不再映射成普通 assistant 文本
- `Read` 这类结果默认仍然 passthrough 到 `userToolResult.text`

- [ ] **Step 3: 实现最小投影逻辑**

规则：

- `userMessage` -> `userMessage`
- `userInteractionResult` -> `userMessage`
- `assistantPlannerMessage` / `assistantQuestionPrompt` / `finalAnswer` -> `assistantMessage`
- `assistantToolCall` / `assistantToolConfirmation` -> `assistantToolUse`
- `toolResult` / `toolError` -> `userToolResult`
- 纯 delta / status / executionStarted 这类不进入 context

- [ ] **Step 4: 在 `toolResult` 投影中接入 transformer contract**

要求：

- 默认 transformer 为 passthrough
- 当前所有工具都走默认逻辑
- 但实现上要允许未来按 `toolName` 注入定制 transformer

- [ ] **Step 5: 运行聚焦测试**

Run: `flutter test test/services/session_context_projector_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/services/session_context_projector.dart test/services/session_context_projector_test.dart
git commit -m "feat: preserve tool transcript structure in context projector"
```

## 任务 3：改造 SessionContextService，统一 current turn 与 recent history 的 context contract

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 写失败测试，锁定跨 turn 历史不再回灌摘要式 assistant 写入结果**

测试构造：

- 历史 completed turn 中有多次 `Write` / `Edit` success
- 当前 turn 是“继续编辑”

断言：

- planner messages / planner context 中仍保留工具链路
- 但不再出现“assistant: 已写入文件：xxx”这种退化形式

可以直接断言结构化 item 类型，或在编码后的模型输入中断言 tool transcript 语义。

- [ ] **Step 2: 运行测试确认当前逻辑失败**

Run: `flutter test test/services/session_context_service_test.dart`

Expected: FAIL，历史 `toolResult` 仍以普通 assistant 文本进入 planner。

- [ ] **Step 3: 将 history segment 构建改为消费 context items，而不是直接消费 ChatMessage**

要求：

- snapshot 仍保持现有 system message 处理方式
- recent completed turns 改为保存结构化 context items
- current turn transcript 也改为同一 contract

- [ ] **Step 4: 保留现有 token budget 行为，但估算基于编码后的文本表示**

可以短期内：

- 先把 context items 编码成稳定文本后再估算 token
- 暂不引入新的 token estimator 维度

重点是不要因为切换了中间表示，就破坏现有 compaction 边界。

- [ ] **Step 5: 确保 date reminder 与 runtime userContext 仍然按既有顺序注入**

顺序要求：

- runtime userContext
- snapshot（若有）
- recent completed turns
- date reminder（当前 turn 前）
- current turn transcript

若实现上需要微调顺序，也要同步更新测试与文档。

- [ ] **Step 6: 运行聚焦测试**

Run: `flutter test test/services/session_context_service_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_context_service.dart test/services/session_context_service_test.dart
git commit -m "feat: use structured tool transcript in session context"
```

## 任务 4：改造 final answer transcript 构建链路

**Files:**
- Modify: `lib/services/transcript_builder_service.dart`
- Modify: `test/services/transcript_builder_service_test.dart`

- [ ] **Step 1: 写失败测试，确认 final answer 构建也保留 tool transcript 结构**

测试要覆盖：

- 当前 turn 内有 `assistantToolCall`
- 紧接着有 `toolResult`
- 最终 `buildFinalAnswerMessages()` 不再把结果变成 assistant 摘要式文本

- [ ] **Step 2: 运行测试确认当前行为失败**

Run: `flutter test test/services/transcript_builder_service_test.dart`

Expected: FAIL，当前还是用扁平 `ChatMessage` 重新投影。

- [ ] **Step 3: 改造 `TranscriptBuilderService`**

要求：

- 保留 system prompt 与 runtime userContext 注入
- transcript 改为从结构化 context item 编码到模型输入
- tool use / tool result 结构必须保真

- [ ] **Step 4: 确保当前 turn 的 date reminder 仍在真实用户消息前**

不要因为改造 transcript 编码层，就丢失既有日期提醒行为。

- [ ] **Step 5: 运行测试**

Run: `flutter test test/services/transcript_builder_service_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/services/transcript_builder_service.dart test/services/transcript_builder_service_test.dart
git commit -m "feat: preserve tool transcript in final answer context"
```

## 任务 5：把 planner / LLM 输入适配到新的结构化 context item

**Files:**
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `lib/models/llm/base_llm.dart`（如需要）
- Modify: `lib/services/chat_service.dart`（如需要）
- Modify: `test/services/turn_harness_test.dart`

- [ ] **Step 1: 阅读 planner 调用栈，确认结构化 context item 最后在哪一层编码为模型输入**

阅读：

- `lib/services/agent_planner_service.dart`
- `lib/models/llm/base_llm.dart`
- `lib/models/llm/*` 中 provider adapter

目标：找到最窄的编码落点，避免把新 contract 泄漏到过多 provider 细节中。

- [ ] **Step 2: 写失败测试，锁定 `Write/Edit` success 不再以 assistant 摘要污染下一轮 planner**

优先改现有：

- `test/services/turn_harness_test.dart`

增加断言：

- 第二轮 planner 可见 transcript 中仍有工具链路
- 但不再只有“已写入文件：xxx”这种 assistant 文字结果

- [ ] **Step 3: 在最窄适配层把 `ModelContextItem` 编码为 provider 可接受的 messages**

建议编码语义：

- `assistantToolUse` -> assistant tool transcript block
- `userToolResult` -> user tool result transcript block
- 普通 user / assistant / system 按原有角色编码

如果现有 provider adapter 还不能直接吃这种结构，先做一层统一编码器，不要把编码逻辑散落进多个 service。

- [ ] **Step 4: 保证 provider-native continuation items 不被破坏**

已有的 openai responses / anthropic / chat completions continuation 逻辑仍需正常工作。

本轮目标是修正“历史 transcript 输入表示”，不是重写 continuation protocol。

- [ ] **Step 5: 运行聚焦测试**

Run: `flutter test test/services/turn_harness_test.dart`

Expected: PASS，且相关 regression 断言通过。

- [ ] **Step 6: Commit**

```bash
git add lib/services/agent_planner_service.dart lib/models/llm/base_llm.dart lib/services/chat_service.dart test/services/turn_harness_test.dart
git commit -m "feat: encode structured tool transcript for planner"
```

## 任务 6：为具体工具接入默认 transformer 出口，但不添加特殊裁剪策略

**Files:**
- Modify: `lib/tools/core/tool_handler.dart`
- Modify: `lib/tools/handlers/write_tool_handler.dart`
- Modify: `lib/tools/handlers/edit_tool_handler.dart`
- Modify: `test/tools/handlers/write_tool_handler_test.dart`
- Modify: `test/tools/handlers/edit_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试，锁定默认 transformer 行为为 passthrough**

示例断言：

- `Write` 未覆盖 transformer 时，context text 仍等于原始 `toolResultText` 或 `summary`
- `Edit` 同理

- [ ] **Step 2: 运行测试确认接口尚不存在**

Run: `flutter test test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/edit_tool_handler_test.dart`

Expected: FAIL。

- [ ] **Step 3: 在 `ToolHandler` 定义层新增可选 context transformer 出口**

例如：

- getter
- 方法
- 或 strategy provider

要求：

- 默认实现为 `null`
- runtime 消费层遇到 `null` 时走默认 passthrough

- [ ] **Step 4: 保持 `Write` / `Edit` 先不自定义**

即：

- 不接特殊裁剪逻辑
- 仅显式依赖默认 passthrough contract

- [ ] **Step 5: 运行测试**

Run: `flutter test test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/edit_tool_handler_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/tools/core/tool_handler.dart lib/tools/handlers/write_tool_handler.dart lib/tools/handlers/edit_tool_handler.dart test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/edit_tool_handler_test.dart
git commit -m "feat: add default tool result context transformer hook"
```

## 任务 7：回归验证与文档同步

**Files:**
- Modify: `README.md`（如架构说明需要补充）
- Modify: `AGENTS.md`（如 prompt/context 规则需要补充）

- [ ] **Step 1: 运行本次改动涉及的测试集合**

Run:

```bash
flutter test \
  test/services/session_context_projector_test.dart \
  test/services/session_context_service_test.dart \
  test/services/transcript_builder_service_test.dart \
  test/services/turn_harness_test.dart \
  test/tools/handlers/write_tool_handler_test.dart \
  test/tools/handlers/edit_tool_handler_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行静态检查**

Run: `flutter analyze`

Expected: 无新增 error；若仓库已有历史 lint，记录其非阻塞性质，不把本轮引入的问题混在一起。

- [ ] **Step 3: 如架构说明发生变化，同步 README / AGENTS**

至少补充：

- context 已从“扁平消息心智模型”提升为“tool transcript 保真投影”
- `tool_result` 允许可选 transformer，默认不转换

- [ ] **Step 4: Commit**

```bash
git add README.md AGENTS.md
git commit -m "docs: describe structured tool transcript context"
```

## 执行说明

本计划写完后，按用户当前偏好直接在当前会话内继续实现，不再等待额外确认，不使用 subagent 模式。
