# AskUserQuestion 消息卡片实施计划

> **给执行型 agent：** 必需子技能：使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步实施本计划。步骤使用复选框（`- [ ]`）追踪进度。

**目标：** 为当前项目增加 Claude Code 风格的 `AskUserQuestion` 能力，让模型可以发出问题型 tool call，应用将其渲染为 assistant 消息卡片，支持单题和多题 wizard，并在用户提交结构化答案后恢复同一个 turn，而不是开启新 turn。

**架构说明：** 保持 `AskUserQuestion` 为模型可见的 tool，但在运行时把它视为 interaction-style tool，而不是普通的立即执行工具。复用现有 `TurnHarness` 的挂起/恢复主链，新增独立的 interaction model 与 coordinator，并通过新的消息内容类型投影 prompt/result，而不是复用 tool confirmation 语义。

**技术栈：** Flutter、Dart、Riverpod、repository 持久化、`flutter_test`

---

## 文件边界

### 新增文件

- `lib/models/interaction/ask_user_question_option.dart`
  - 表示单个问题选项，并承载推荐标签解析后的结果。
- `lib/models/interaction/ask_user_question_item.dart`
  - 表示单个问题，包含 `question/header/multiSelect/options`。
- `lib/models/interaction/ask_user_question_request.dart`
  - 运行时问题请求模型，用于 prompt 消息持久化和恢复。
- `lib/models/interaction/ask_user_question_response.dart`
  - 用户结构化回答模型，用于 transcript 注入和 turn 恢复。
- `lib/models/interaction/question_card_payload.dart`
  - prompt/result 渲染使用的稳定消息 payload 包装结构。
- `lib/controllers/chat_interaction_coordinator.dart`
  - AskUserQuestion 卡片的提交/取消入口。
- `lib/providers/chat_interaction_providers.dart`
  - 以 message 或 turn 为 key 的问答卡片内存草稿状态。
- `lib/widgets/interaction/ask_user_question_card.dart`
  - 承载单题和多题 wizard 的 assistant 消息卡片组件。
- `test/models/interaction/ask_user_question_request_test.dart`
- `test/controllers/chat_interaction_coordinator_test.dart`
- `test/widgets/interaction/ask_user_question_card_test.dart`

### 修改文件

- `lib/models/tool/tool_definition.dart`
  - 增加 execution-mode 元数据，避免 runtime 通过硬编码工具名识别 interaction tool。
- `lib/models/chat_turn.dart`
  - 增加 `awaitingUserInteraction` turn 状态。
- `lib/models/chat_event.dart`
  - 增加问题交互的 prompt/result 事件类型。
- `lib/models/response/message_content_type.dart`
  - 增加 `askUserQuestionPrompt` 和 `askUserQuestionResult`。
- `lib/services/turn_harness.dart`
  - 识别 interaction tool、挂起 turn、发出 prompt 事件、在用户回答后恢复。
- `lib/services/tool_orchestrator_service.dart`
  - 显式绕开或拒绝 interaction tool，保持立即执行路径的语义纯净。
- `lib/controllers/chat_send_coordinator.dart`
  - 把 prompt/result 事件投影为消息，不再复用 confirmation 语义来承载问题卡片。
- `lib/services/chat_block_builder.dart`
  - 构建 prompt/result payload 对应的 render block。
- `lib/widgets/chat_message_list.dart`
  - 在消息列表中渲染 `AskUserQuestionCard`。
- `lib/providers/chat_providers.dart`
  - 将 `ChatInteractionCoordinator` 和相关 provider 接入现有组合入口。
- `lib/providers/chat_send_state_providers.dart`
  - 如有需要，为 `awaitingUserInteraction` 扩展 send phase。
- `test/services/turn_harness_test.dart`
- `test/services/tool_orchestrator_service_test.dart`
- `test/services/chat_block_builder_test.dart`
- `test/models/chat_turn_test.dart`
- `test/repositories/chat_turn_repository_test.dart`
- `test/repositories/chat_turn_step_repository_test.dart`

### 实现完成后需要同步更新的文档

- `AGENTS.md`
- `README.md`
- `docs/superpowers/specs/2026-04-14-ask-user-question-message-card-design.md`

---

## 任务 1：补齐 interaction model 和执行元数据

**文件：**
- 新增：`lib/models/interaction/ask_user_question_option.dart`
- 新增：`lib/models/interaction/ask_user_question_item.dart`
- 新增：`lib/models/interaction/ask_user_question_request.dart`
- 新增：`lib/models/interaction/ask_user_question_response.dart`
- 新增：`lib/models/interaction/question_card_payload.dart`
- 修改：`lib/models/tool/tool_definition.dart`
- 测试：`test/models/interaction/ask_user_question_request_test.dart`

- [ ] **步骤 1：先写失败测试**

新增模型测试，至少覆盖以下点：

```dart
test('AskUserQuestionRequest 可以解析 1-4 个问题、multiSelect 和 options', () {
  final request = AskUserQuestionRequest.fromJson({
    'questions': [
      {
        'question': 'Which storage layer should we use?',
        'header': 'Storage',
        'multiSelect': false,
        'options': [
          {'label': 'SQLite', 'description': 'Local relational store'},
          {'label': 'Isar (Recommended)', 'description': 'Fast object store'},
        ],
      },
    ],
    'agentTurnId': 42,
  });

  expect(request.questions.single.options[1].isRecommended, isTrue);
});

test('QuestionCardPayload 能稳定 round-trip prompt payload', () {
  // 验证 turn id、step id、questions、status 编解码后不丢失。
});
```

- [ ] **步骤 2：运行模型测试，确认失败**

运行：

```bash
fvm flutter test test/models/interaction/ask_user_question_request_test.dart
```

预期：FAIL，因为 interaction model 还不存在。

- [ ] **步骤 3：实现 interaction model 文件**

实现最小可用 DTO，要求包括：

- JSON 编解码
- 推荐标签解析 helper
- 可存入 `ChatMessage.payloadJson` 的 payload wrapper
- 能表达单选、多选和 `Other` 的 response 结构

- [ ] **步骤 4：给 ToolDefinition 增加 execution metadata**

在 `ToolDefinition` 中扩展稳定的执行模式字段，例如：

```dart
enum ToolExecutionMode {
  immediate,
  requiresConfirmation,
  userInteraction,
}
```

现有工具默认保持兼容，不要让旧行为回退。

- [ ] **步骤 5：重新运行模型测试**

运行：

```bash
fvm flutter test test/models/interaction/ask_user_question_request_test.dart
```

预期：PASS。

- [ ] **步骤 6：提交模型层改动**

```bash
git add \
  lib/models/interaction/ask_user_question_option.dart \
  lib/models/interaction/ask_user_question_item.dart \
  lib/models/interaction/ask_user_question_request.dart \
  lib/models/interaction/ask_user_question_response.dart \
  lib/models/interaction/question_card_payload.dart \
  lib/models/tool/tool_definition.dart \
  test/models/interaction/ask_user_question_request_test.dart
git commit -m "feat: add ask user question interaction models"
```

---

## 任务 2：为 turn / event / message 增加等待用户交互的状态

**文件：**
- 修改：`lib/models/chat_turn.dart`
- 修改：`lib/models/chat_event.dart`
- 修改：`lib/models/response/message_content_type.dart`
- 修改：`test/models/chat_turn_test.dart`
- 修改：`test/repositories/chat_turn_repository_test.dart`
- 修改：`test/repositories/chat_turn_step_repository_test.dart`

- [ ] **步骤 1：先补失败测试，锁定新状态和序列化行为**

增加以下类型的测试：

```dart
test('ChatTurnStatus 能从持久化数据解析 awaitingUserInteraction', () {
  // fromMap 后能正确得到新 enum。
});

test('MessageContentType 能 round-trip askUserQuestionPrompt 和 askUserQuestionResult', () {
  // 确保 wireName/fromString 稳定。
});
```

- [ ] **步骤 2：运行相关测试，确认失败**

运行：

```bash
fvm flutter test test/models/chat_turn_test.dart
fvm flutter test test/repositories/chat_turn_repository_test.dart
fvm flutter test test/repositories/chat_turn_step_repository_test.dart
```

预期：FAIL，因为还没有新状态和新 content type。

- [ ] **步骤 3：实现新的 waiting-state / event / message enum**

新增：

- `ChatTurnStatus.awaitingUserInteraction`
- `ChatEventType.assistantQuestionPrompt`
- `ChatEventType.userInteractionResult`
- `MessageContentType.askUserQuestionPrompt`
- `MessageContentType.askUserQuestionResult`

注意保持旧持久化值兼容。

- [ ] **步骤 4：重新运行相关测试**

运行：

```bash
fvm flutter test test/models/chat_turn_test.dart
fvm flutter test test/repositories/chat_turn_repository_test.dart
fvm flutter test test/repositories/chat_turn_step_repository_test.dart
```

预期：PASS。

- [ ] **步骤 5：提交持久化基础语义**

```bash
git add \
  lib/models/chat_turn.dart \
  lib/models/chat_event.dart \
  lib/models/response/message_content_type.dart \
  test/models/chat_turn_test.dart \
  test/repositories/chat_turn_repository_test.dart \
  test/repositories/chat_turn_step_repository_test.dart
git commit -m "feat: add user interaction waiting state"
```

---

## 任务 3：让 TurnHarness 能挂起并恢复 AskUserQuestion

**文件：**
- 修改：`lib/services/turn_harness.dart`
- 修改：`lib/services/tool_orchestrator_service.dart`
- 修改：`test/services/turn_harness_test.dart`
- 修改：`test/services/tool_orchestrator_service_test.dart`

- [ ] **步骤 1：先写 TurnHarness 的失败测试**

至少覆盖这两个路径：

```dart
test('TurnHarness 遇到 AskUserQuestion 时会发出 assistantQuestionPrompt 并停在 awaitingUserInteraction', () async {
  // planner 返回 AskUserQuestion tool call
  // 断言 turn 被挂起且 prompt event 已发出
});

test('resumeAfterQuestionAnswered 会把答案注入当前 turn 并继续 loop', () async {
  // 从挂起态恢复，最后拿到 final answer
});
```

- [ ] **步骤 2：先写 ToolOrchestratorService 的失败测试**

防止立即执行路径被污染：

```dart
test('interaction tool 不会走 ToolOrchestratorService 的普通执行路径', () async {
  // 应显式 guard，而不是像普通 tool 那样继续 execute。
});
```

- [ ] **步骤 3：运行 service 测试，确认失败**

运行：

```bash
fvm flutter test test/services/turn_harness_test.dart
fvm flutter test test/services/tool_orchestrator_service_test.dart
```

预期：FAIL，因为当前没有 AskUserQuestion 的挂起/恢复逻辑。

- [ ] **步骤 4：在 TurnHarness 中实现 AskUserQuestion 分支**

最小实现要求：

- 识别 `ToolExecutionMode.userInteraction`
- 创建或更新 turn step
- 发出 `assistantQuestionPrompt`
- 将 turn 置为 `awaitingUserInteraction`

并新增恢复接口，例如：

```dart
Stream<ChatEvent> resumeAfterQuestionAnswered({
  required int turnId,
  required AskUserQuestionRequest request,
  required AskUserQuestionResponse response,
  required ChatConfig config,
})
```

- [ ] **步骤 5：保持 ToolOrchestratorService 语义收敛**

为 interaction tool 增加显式 guard，确保它不会默默进入普通立即执行路径。

- [ ] **步骤 6：重新运行 service 测试**

运行：

```bash
fvm flutter test test/services/turn_harness_test.dart
fvm flutter test test/services/tool_orchestrator_service_test.dart
```

预期：PASS。

- [ ] **步骤 7：提交 runtime suspension/resume 改动**

```bash
git add \
  lib/services/turn_harness.dart \
  lib/services/tool_orchestrator_service.dart \
  test/services/turn_harness_test.dart \
  test/services/tool_orchestrator_service_test.dart
git commit -m "feat: suspend turns for ask user question"
```

---

## 任务 4：把 prompt / result 事件投影为聊天消息

**文件：**
- 修改：`lib/controllers/chat_send_coordinator.dart`
- 修改：`lib/services/chat_block_builder.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 修改：`test/services/chat_block_builder_test.dart`

- [ ] **步骤 1：先补 block builder 的失败测试**

至少覆盖：

```dart
test('question prompt payload 会构建 ask-user-question block', () {
  // 新内容类型应走新的卡片渲染分支。
});

test('question result payload 会渲染紧凑的答案摘要 block', () {
  // 提交后的结果应可回放。
});
```

- [ ] **步骤 2：运行 UI 投影测试，确认失败**

运行：

```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

预期：FAIL，因为当前还没有新内容类型的映射。

- [ ] **步骤 3：扩展 ChatSendCoordinator 的事件投影**

处理：

- `assistantQuestionPrompt` → `MessageContentType.askUserQuestionPrompt`
- `userInteractionResult` → `MessageContentType.askUserQuestionResult`

不要复用 `actionConfirmation` 或 `toolResult`。

- [ ] **步骤 4：扩展 block builder 和消息列表路由**

为新的 content type 增加独立 render 分支。prompt 分支最终指向 `AskUserQuestionCard`，result 分支先做简洁的摘要展示即可。

- [ ] **步骤 5：重新运行投影测试**

运行：

```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

预期：PASS。

- [ ] **步骤 6：提交 prompt/result 投影**

```bash
git add \
  lib/controllers/chat_send_coordinator.dart \
  lib/services/chat_block_builder.dart \
  lib/widgets/chat_message_list.dart \
  test/services/chat_block_builder_test.dart
git commit -m "feat: project ask user question messages"
```

---

## 任务 5：增加卡片草稿状态和提交流程协调器

**文件：**
- 新增：`lib/controllers/chat_interaction_coordinator.dart`
- 新增：`lib/providers/chat_interaction_providers.dart`
- 修改：`lib/providers/chat_providers.dart`
- 测试：`test/controllers/chat_interaction_coordinator_test.dart`

- [ ] **步骤 1：先写 coordinator 的失败测试**

至少覆盖：

```dart
test('submitQuestionAnswers 会恢复对应的挂起 turn', () async {
  // 断言 coordinator 调用了 TurnHarness.resumeAfterQuestionAnswered。
});

test('cancelQuestionPrompt 会清理本地草稿状态并恢复 idle UI', () async {
  // 断言不会污染无关 send flow。
});
```

- [ ] **步骤 2：运行 coordinator 测试，确认失败**

运行：

```bash
fvm flutter test test/controllers/chat_interaction_coordinator_test.dart
```

预期：FAIL，因为 coordinator 和 provider 还不存在。

- [ ] **步骤 3：实现草稿状态 provider**

按 message id 或 turn id 维护：

- 当前题索引
- 已选项
- `Other` 文本
- 当前题是否可提交

这些状态仅保存在内存里，直到用户点击提交。

- [ ] **步骤 4：实现 ChatInteractionCoordinator**

提供类似以下接口：

```dart
Future<void> submitQuestionAnswers(ChatMessage message);
Future<void> cancelQuestionPrompt(ChatMessage message);
```

并接入 `TurnHarness.resumeAfterQuestionAnswered(...)` 与草稿 provider。

- [ ] **步骤 5：接入 provider 组合入口**

把 coordinator 和相关 provider 接入 `chat_providers.dart`，但不要让 `ChatController` 重新变胖。

- [ ] **步骤 6：重新运行 coordinator 测试**

运行：

```bash
fvm flutter test test/controllers/chat_interaction_coordinator_test.dart
```

预期：PASS。

- [ ] **步骤 7：提交 interaction coordination**

```bash
git add \
  lib/controllers/chat_interaction_coordinator.dart \
  lib/providers/chat_interaction_providers.dart \
  lib/providers/chat_providers.dart \
  test/controllers/chat_interaction_coordinator_test.dart
git commit -m "feat: add ask user question interaction coordinator"
```

---

## 任务 6：实现单题卡片 UI 和 Other 输入

**文件：**
- 新增：`lib/widgets/interaction/ask_user_question_card.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 测试：`test/widgets/interaction/ask_user_question_card_test.dart`

- [ ] **步骤 1：先写单题卡片的失败测试**

至少覆盖：

```dart
testWidgets('单选问题能渲染选项并提交选中的答案', (tester) async {
  // 选择一项并提交，断言回调拿到答案。
});

testWidgets('选择 Other 后会出现输入框并提交自定义答案', (tester) async {
  // 选择 Other、输入文本、提交。
});
```

- [ ] **步骤 2：运行 widget 测试，确认失败**

运行：

```bash
fvm flutter test test/widgets/interaction/ask_user_question_card_test.dart
```

预期：FAIL，因为卡片组件还不存在。

- [ ] **步骤 3：实现最小可用卡片 UI**

要求：

- 显示 header 与 question
- 支持单选 / 多选选项列表
- 自动追加 `Other`
- 当前题有效前禁用提交

- [ ] **步骤 4：把 prompt 消息接到新卡片**

更新 `chat_message_list.dart`，让 `askUserQuestionPrompt` 消息渲染 `AskUserQuestionCard`，并通过 `ChatInteractionCoordinator` 提交。

- [ ] **步骤 5：重新运行 widget 测试**

运行：

```bash
fvm flutter test test/widgets/interaction/ask_user_question_card_test.dart
```

预期：PASS。

- [ ] **步骤 6：提交单题 UI**

```bash
git add \
  lib/widgets/interaction/ask_user_question_card.dart \
  lib/widgets/chat_message_list.dart \
  test/widgets/interaction/ask_user_question_card_test.dart
git commit -m "feat: add ask user question card ui"
```

---

## 任务 7：实现多题 wizard 和统一提交

**文件：**
- 修改：`lib/widgets/interaction/ask_user_question_card.dart`
- 修改：`lib/providers/chat_interaction_providers.dart`
- 修改：`test/widgets/interaction/ask_user_question_card_test.dart`

- [ ] **步骤 1：先补多题 wizard 的失败测试**

至少覆盖：

```dart
testWidgets('多题卡片会按 header 逐题推进，并在最后统一提交', (tester) async {
  // 填写 Q1、下一步、填写 Q2、最终提交，只触发一次提交回调。
});

testWidgets('多题卡片支持返回上一题且保留草稿答案', (tester) async {
  // 前进后返回，确认已选内容仍然存在。
});
```

- [ ] **步骤 2：运行 widget 测试，确认失败**

运行：

```bash
fvm flutter test test/widgets/interaction/ask_user_question_card_test.dart
```

预期：FAIL，因为还没有 wizard 行为。

- [ ] **步骤 3：实现 wizard 导航**

增加：

- 顶部 header chips / segmented progress
- 上一步 / 下一步
- 每题最低校验
- 仅在最后一题允许统一提交

- [ ] **步骤 4：在 provider 中保留多题草稿状态**

使用内存草稿状态保存跨题答案，不要在切题时就写入消息 payload。

- [ ] **步骤 5：重新运行 widget 测试**

运行：

```bash
fvm flutter test test/widgets/interaction/ask_user_question_card_test.dart
```

预期：PASS。

- [ ] **步骤 6：提交 wizard 行为**

```bash
git add \
  lib/widgets/interaction/ask_user_question_card.dart \
  lib/providers/chat_interaction_providers.dart \
  test/widgets/interaction/ask_user_question_card_test.dart
git commit -m "feat: support multi-question ask user question wizard"
```

---

## 任务 8：补齐 transcript、trace 和文档同步

**文件：**
- 修改：`lib/services/turn_harness.dart`
- 修改：`lib/controllers/chat_send_coordinator.dart`
- 修改：`AGENTS.md`
- 修改：`README.md`
- 修改：`docs/superpowers/specs/2026-04-14-ask-user-question-message-card-design.md`
- 测试：`test/services/turn_harness_test.dart`
- 测试：`test/services/chat_block_builder_test.dart`

- [ ] **步骤 1：先补失败的集成断言**

扩展 service 测试，验证提交答案后：

```dart
test('interaction result 会先生成 transcript-visible 的答案摘要，再继续最终回答', () async {
  // 断言出现 "User answered AskUserQuestion" 风格的上下文摘要。
});
```

- [ ] **步骤 2：运行相关集成测试，确认失败**

运行：

```bash
fvm flutter test test/services/turn_harness_test.dart
fvm flutter test test/services/chat_block_builder_test.dart
```

预期：FAIL，直到 transcript/result summary 完整接通。

- [ ] **步骤 3：补齐 interaction result 的最终投影**

确保恢复路径会写入：

- step completion / result summary
- transcript 可见的结构化答案摘要
- 可供 UI 回放的 result payload
- 与 tool confirmation 区分开的 trace 事件

- [ ] **步骤 4：更新文档**

同步更新：

- `AGENTS.md` 中的 interactive checkpoint 边界
- `README.md` 中 AskUserQuestion 能力说明
- 如实现细节偏离设计，回写 spec

- [ ] **步骤 5：运行完整定向验证**

运行：

```bash
fvm flutter test \
  test/models/interaction/ask_user_question_request_test.dart \
  test/models/chat_turn_test.dart \
  test/repositories/chat_turn_repository_test.dart \
  test/repositories/chat_turn_step_repository_test.dart \
  test/services/tool_orchestrator_service_test.dart \
  test/services/turn_harness_test.dart \
  test/services/chat_block_builder_test.dart \
  test/controllers/chat_interaction_coordinator_test.dart \
  test/widgets/interaction/ask_user_question_card_test.dart
```

然后运行：

```bash
fvm flutter analyze
```

预期：所有定向测试 PASS，analyze 无错误。

- [ ] **步骤 6：提交完整功能**

```bash
git add \
  lib/models \
  lib/services \
  lib/controllers \
  lib/providers \
  lib/widgets \
  test \
  AGENTS.md \
  README.md \
  docs/superpowers/specs/2026-04-14-ask-user-question-message-card-design.md
git commit -m "feat: add ask user question message card flow"
```

---

## 执行注意事项

- 不要把 AskUserQuestion 重新塞进 `ToolInvocation` 或 `actionConfirmation`。
- 不要让 AskUserQuestion 像普通立即返回工具一样走 `ToolHandler.execute()`。
- 保持 `ToolOrchestratorService` 语义收敛；turn 的挂起/恢复仍由 `TurnHarness` 负责。
- 草稿答案只放在 provider 中，提交后再持久化最终结果。
- 优先做最小兼容扩展，不要顺手扩大 UI 重构范围。

## 审阅说明

本计划已在当前会话中生成，但没有额外派发 plan reviewer 子代理。如果你希望在编码前再做一次计划审阅，可以单独提出，我再补这一轮。
