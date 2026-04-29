# ChatSendCoordinator Headless Live Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一层以 `ChatSendCoordinator` 为主入口、真实 provider API 为后端、真实 test DB 为存储的 headless live integration 测试基建，并先落地首批高风险 scenario case。

**Architecture:** 保持 `DefaultChatSendCoordinator -> TurnHarness -> AgentPlannerService -> SessionContextService -> repositories/SQLite` 的真实主链路，不引入 fake provider 裁判层。测试资产按 `scenario case + provider matrix` 组织，默认只跑被触及 style，CI/手动回归再跑三类 style 固定全集。

**Tech Stack:** Flutter test, Riverpod ProviderContainer, SQLite test DB, ConfigurableHttpLLM, 本地测试工作目录/网页夹具, shell wrapper scripts

---

## 当前进展检查点

截至当前 worktree，会话已完成以下内容：

- 已搭好 `headless live integration` 基础 harness
- 已接通真实 `ChatSendCoordinator -> TurnHarness -> ConfigurableHttpLLM -> SQLite` 主链路
- 已补齐基础场景模型、workspace fixture、state snapshot 与 ledger assertion helper
- 已新增 `news_multi_tool` 首个真实 live scenario 骨架，并在 `deepseek-anthropic` 上跑通真实两次 `web_search` + continuation + final answer
- 已新增并跑通 `ask_user_resume` 真实 live scenario：
  - `assistantQuestionPrompt -> submitQuestionAnswers() -> userInteractionResult -> finalAnswer`
  - 已验证 prompt 卡会在恢复后被 result 卡原位替换，断言需区分 waiting/resumed 两个快照
- 已从 `main/origin/main` 合入并发事件写库修复：
  - `57cfdaa8 fix: serialize chat event appends per turn to prevent sequence collision`
- 已确认一个关键 live 结论：
  - 真实 provider 当前稳定暴露的是“多轮 continuation 链路覆盖”
  - 不应把 live case 写死成“同一 decision batch 内必须一次吐出多个 tool call”
  - `providerResponseId/providerCallId` 断言仍然重要，但 live test 应优先验证链路闭合，而不是模型决策形状

当前主线阻塞点不是 provider wire 不通，而是 **Agent Loop 内部语义仍缺少“decision batch”这一层的稳定表达**：

- `providerResponseId` 已足够表达“同一次模型决策批次”
- `providerCallId` 已足够表达“该批次内的具体调用”
- 但当前 `step / event / projection / live assertion` 对“批次语义”的承载仍不统一

因此，下一阶段需要先插入一个受控子任务：

- 先补一份最小 `DecisionBatch` 领域模型设计
- 先统一语义口径：
  - `step = 单个执行单元`
  - `providerResponseId = batch key`
  - `providerCallId = leaf key`
- 再回到 live integration 主线，继续补 `ask_user resume`、`mixed success/failure`、`file ops` 等 case

这不是偏离 live test 主线，而是为避免后续继续在错误语义上堆 case。

## 已完成任务

- `Task 1` 基础测试入口与目录骨架：已完成
- `Task 2` 真实 ProviderContainer 与发送链路：已完成
- `Task 3` `ScenarioCase + ProviderMatrix` 基础模型：已完成
- `Task 4` 测试工作目录与真实工具夹具基础版：已完成
- `Task 5` 链路状态断言工具基础版：已完成
- `Task 6` 首个高风险 live 场景的第一阶段：已完成
  - `news_multi_tool` 已具备稳定的 provider-native continuation 覆盖断言
  - `ask_user_resume` 已具备稳定的 waiting/resume 断言

## 当前进行中的任务

- `Task 7` 扩充下一批高风险场景

下一优先级建议：

- `mixed_success_failure`
  - 验证真实 provider 在某个工具失败后，turn 是否还能继续/收敛，且 providerCallId 链不丢
- `file_ops_real_workspace`
  - 验证更接近真实工作区的 `Read/Write/Edit/LS/Grep/Glob` 调用与落库

## 当前插入的子任务

- 新增一份最小化设计稿：
  - `DecisionBatch` 先作为领域模型与 projection / assertion 语义，不立即落库
- 目标：
  - 避免继续用 `step 数 == 批次数` 之类错误假设写 live test
  - 为后续 `ChatBlockBuilder`、live assertions、resume 场景提供统一标准

---

## 文件结构

### 新增文件

- `test/integration/chat_send_live/chat_send_live_test_harness.dart`
  - headless live integration 的统一测试 harness
  - 负责 test DB、ProviderContainer、测试工作目录、provider 选择、消息发送等待、结果读取
- `test/integration/chat_send_live/chat_send_live_scenario.dart`
  - `ScenarioCase`、`ProviderMatrixTarget`、断言模型定义
- `test/integration/chat_send_live/chat_send_live_fixture_builder.dart`
  - 测试工作目录、文件树、网页夹具、最小环境准备
- `test/integration/chat_send_live/chat_send_live_assertions.dart`
  - 针对 `chat_turns / chat_turn_steps / chat_events / messages` 的链路状态断言工具
- `test/integration/chat_send_live/scenarios/news_multi_tool_scenario.dart`
  - “最新新闻搜索 -> 多 tool continuation -> 汇总” 场景
- `test/integration/chat_send_live/scenarios/ask_user_resume_scenario.dart`
  - ask-user resume 场景
- `test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart`
  - `Read/Write/Edit/LS/Grep/Glob` 真实工作目录场景
- `test/integration/chat_send_live/scenarios/mixed_success_failure_scenario.dart`
  - tool success / error mixed continuation 场景
- `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`
  - Anthropic style 入口测试
- `test/integration/chat_send_live/chat_send_live_responses_test.dart`
  - Responses style 入口测试
- `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
  - Chat Completions style 入口测试
- `scripts/run_headless_live_integration_tests.sh`
  - 按 style / provider / scenario 过滤运行的脚本

### 修改文件

- `config/local_defaults.json`
  - 如有必要，补充 headless live integration 可用 provider 选择说明，不新增正式架构复杂度
- `AGENTS.md`
  - 增补新的 headless live integration 运行规则与“默认只跑被触及 style，回归跑三类全集”的约束
- `README.md`
  - 补充测试分层说明与推荐命令
- `docs/architecture/agent-loop-boundaries-and-decoupling.md`
  - 补充该测试层在总体分层中的位置

### 复用/参考文件

- `lib/controllers/chat_send_coordinator.dart`
- `lib/services/turn_harness.dart`
- `lib/services/agent_planner_service.dart`
- `lib/services/session_context_service.dart`
- `lib/models/llm/configurable_http_llm.dart`
- `test/models/llm/configurable_http_llm_live_test.dart`
- `test/services/simulated_turn_projection_integration_test.dart`
- `scripts/run_live_llm_contract_tests.sh`

## 实施原则

- 场景优先，不按 provider 复制测试资产
- 真实 provider API 必须参与 planner / continuation / resume
- 真实 test DB 必须参与 turn / step / event / message 落库
- 工具优先真实执行，只有高副作用/高不确定性工具才替身
- 不以最终 assistant 文本逐字正确作为主要断言
- 每个任务都先补测试或 harness 能力，再补实现，再验证

### Task 1: 建立基础测试入口与目录骨架

**Files:**
- Create: `test/integration/chat_send_live/chat_send_live_test_harness.dart`
- Create: `test/integration/chat_send_live/chat_send_live_scenario.dart`
- Create: `test/integration/chat_send_live/chat_send_live_fixture_builder.dart`
- Create: `test/integration/chat_send_live/chat_send_live_assertions.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写最小 failing test，证明 live integration 测试目录与 tags 可被识别**

```dart
test(
  'headless live harness boots with a real test db',
  () async {
    final harness = await ChatSendLiveTestHarness.bootstrap();
    expect(harness.databasePath, isNotEmpty);
    await harness.dispose();
  },
  tags: const ['live-headless-agent'],
);
```

- [ ] **Step 2: 运行单测确认失败**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "headless live harness boots with a real test db"`

Expected: FAIL，提示 harness / imports / file not found

- [ ] **Step 3: 实现最小 harness 骨架**

实现内容：

- `ChatSendLiveTestHarness.bootstrap()`
- 独立 test DB 初始化
- `ProviderContainer` 创建
- `dispose()` 清理

- [ ] **Step 4: 运行单测确认通过**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "headless live harness boots with a real test db"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/chat_send_live_test_harness.dart \
  test/integration/chat_send_live/chat_send_live_scenario.dart \
  test/integration/chat_send_live/chat_send_live_fixture_builder.dart \
  test/integration/chat_send_live/chat_send_live_assertions.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: scaffold headless live integration harness"
```

### Task 2: 接通真实 ProviderContainer 与 ChatSendCoordinator 发送链路

**Files:**
- Modify: `test/integration/chat_send_live/chat_send_live_test_harness.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写 failing test，证明可以从 `ChatSendCoordinator.sendMessage()` 发起一次真实 turn**

```dart
test(
  'sendMessage creates a real turn and persists user message',
  () async {
    final harness = await ChatSendLiveTestHarness.bootstrap(
      providerId: 'deepseek-anthropic',
    );
    await harness.sendUserMessage('帮我搜索下 Google 最新新闻');
    final turns = await harness.listTurns();
    final messages = await harness.listMessages();
    expect(turns, isNotEmpty);
    expect(messages.any((m) => m.isUser), isTrue);
    await harness.dispose();
  },
  tags: const ['live-headless-agent'],
);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "sendMessage creates a real turn and persists user message"`

Expected: FAIL，提示 send helper / provider wiring 缺失

- [ ] **Step 3: 在 harness 中接通真实发送链路**

实现内容：

- 构建 `ProviderContainer`
- 注入真实 `DefaultChatSendCoordinator`
- 注入真实 `turnHarnessProvider`
- 提供 `sendUserMessage()` / `waitForTurnSettled()` / `listTurns()` / `listMessages()`

- [ ] **Step 4: 运行测试确认通过**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "sendMessage creates a real turn and persists user message"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/chat_send_live_test_harness.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: wire chat send coordinator into live harness"
```

### Task 3: 定义 `ScenarioCase + ProviderMatrix` 模型

**Files:**
- Modify: `test/integration/chat_send_live/chat_send_live_scenario.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_test_harness.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写 failing test，证明同一 scenario 可挂多个 provider target**

```dart
test('scenario exposes multiple provider targets', () {
  final scenario = buildNewsMultiToolScenario();
  expect(scenario.providerTargets.length, greaterThan(1));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "scenario exposes multiple provider targets"`

Expected: FAIL，`ScenarioCase` 尚未定义完整

- [ ] **Step 3: 实现场景与 provider matrix 模型**

实现内容：

- `ScenarioCase`
- `ProviderMatrixTarget`
- `FixtureSpec`
- `ScenarioAssertionPlan`
- `ScenarioFollowUpAction`

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "scenario exposes multiple provider targets"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/chat_send_live_scenario.dart \
  test/integration/chat_send_live/chat_send_live_test_harness.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: add scenario case and provider matrix model"
```

### Task 4: 落地测试工作目录与真实工具夹具

**Files:**
- Modify: `test/integration/chat_send_live/chat_send_live_fixture_builder.dart`
- Create: `test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写 failing test，证明 harness 能创建独立工作目录并准备真实文件树**

```dart
test('fixture builder creates real workspace files for file tools', () async {
  final harness = await ChatSendLiveTestHarness.bootstrap();
  final workspace = await harness.prepareWorkspaceFixture(
    files: {
      'docs/spec.md': 'initial content',
      'notes/todo.md': 'todo',
    },
  );
  expect(File('${workspace.path}/docs/spec.md').existsSync(), isTrue);
  await harness.dispose();
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "fixture builder creates real workspace files for file tools"`

Expected: FAIL

- [ ] **Step 3: 实现 fixture builder**

实现内容：

- 独立 temp workspace
- 文件树创建
- 可选本地网页夹具目录
- 清理逻辑

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "fixture builder creates real workspace files for file tools"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/chat_send_live_fixture_builder.dart \
  test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: support real workspace fixtures for live scenarios"
```

### Task 5: 实现链路状态断言工具

**Files:**
- Modify: `test/integration/chat_send_live/chat_send_live_assertions.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写 failing test，证明可以对 turn / step / event 序列做结构断言**

```dart
test('assertion helpers inspect persisted turn ledger state', () async {
  final harness = await ChatSendLiveTestHarness.bootstrap();
  final state = await harness.snapshotState();
  expect(() => expectTurnState(state, expectedStatus: ChatTurnStatus.running),
      returnsNormally);
  await harness.dispose();
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "assertion helpers inspect persisted turn ledger state"`

Expected: FAIL

- [ ] **Step 3: 实现断言 helpers**

实现内容：

- `expectTurnState(...)`
- `expectStepSequence(...)`
- `expectEventTypes(...)`
- `expectProviderIdsAligned(...)`
- `expectNoPlannerRequestFailure(...)`

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "assertion helpers inspect persisted turn ledger state"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/chat_send_live_assertions.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: add live integration ledger assertions"
```

### Task 6: 落地首个高风险场景 `news_multi_tool`

**Files:**
- Create: `test/integration/chat_send_live/scenarios/news_multi_tool_scenario.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写 failing 场景测试**

```dart
test(
  'news multi-tool scenario preserves anthropic multi-tool continuation state',
  () async {
    final harness = await ChatSendLiveTestHarness.bootstrap(
      providerId: 'deepseek-anthropic',
    );
    await harness.runScenario(buildNewsMultiToolScenario());
    final state = await harness.snapshotState();
    expectNoPlannerRequestFailure(state);
    expectStepSequence(state, minimumCount: 2);
    expectProviderIdsAligned(state);
    await harness.dispose();
  },
  tags: const ['live-headless-agent'],
);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "news multi-tool scenario preserves anthropic multi-tool continuation state"`

Expected: FAIL，缺少场景与运行器

- [ ] **Step 3: 实现场景与 runner**

实现内容：

- 场景用户消息
- 默认工具集合
- turn settled 等待
- 链路状态断言

- [ ] **Step 4: 运行测试确认通过**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "news multi-tool scenario preserves anthropic multi-tool continuation state"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/scenarios/news_multi_tool_scenario.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: add live multi-tool continuation scenario"
```

### Task 7: 落地 ask-user resume 场景

**Files:**
- Create: `test/integration/chat_send_live/scenarios/ask_user_resume_scenario.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_responses_test.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`

- [ ] **Step 1: 写 failing 场景测试**

```dart
test(
  'ask-user resume scenario persists prompt, answer, and resumed turn state',
  () async {
    final harness = await ChatSendLiveTestHarness.bootstrap(
      providerId: 'deepseek-anthropic',
    );
    await harness.runScenario(buildAskUserResumeScenario());
    final state = await harness.snapshotState();
    expectEventTypes(
      state,
      includesInOrder: [
        ChatEventType.assistantQuestionPrompt,
        ChatEventType.userInteractionResult,
      ],
    );
    await harness.dispose();
  },
  tags: const ['live-headless-agent'],
);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "ask-user resume scenario persists prompt, answer, and resumed turn state"`

Expected: FAIL

- [ ] **Step 3: 实现场景与 resume driver**

实现内容：

- 等待 ask-user 提示落库
- 读取 prompt message
- 调用 `submitQuestionAnswers()`
- 等待 resumed turn 收敛

- [ ] **Step 4: 运行测试确认通过**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "ask-user resume scenario persists prompt, answer, and resumed turn state"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/scenarios/ask_user_resume_scenario.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart \
  test/integration/chat_send_live/chat_send_live_responses_test.dart \
  test/integration/chat_send_live/chat_send_live_chat_completions_test.dart
git commit -m "test: add headless ask-user resume scenario"
```

### Task 8: 落地 mixed success/failure 场景

**Files:**
- Create: `test/integration/chat_send_live/scenarios/mixed_success_failure_scenario.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写 failing 场景测试**

```dart
test(
  'mixed success failure scenario persists both toolResult and toolError states',
  () async {
    final harness = await ChatSendLiveTestHarness.bootstrap(
      providerId: 'deepseek-anthropic',
    );
    await harness.runScenario(buildMixedSuccessFailureScenario());
    final state = await harness.snapshotState();
    expectEventTypes(
      state,
      includes: [ChatEventType.toolResult, ChatEventType.toolError],
    );
    await harness.dispose();
  },
  tags: const ['live-headless-agent'],
);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "mixed success failure scenario persists both toolResult and toolError states"`

Expected: FAIL

- [ ] **Step 3: 实现场景**

实现内容：

- 至少一个真实成功工具
- 至少一个可重复失败路径
- 断言 continuation 后没有 planner wire failure

- [ ] **Step 4: 运行测试确认通过**

Run: `LIVE_LLM_PROVIDER_IDS=deepseek-anthropic fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "mixed success failure scenario persists both toolResult and toolError states"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/scenarios/mixed_success_failure_scenario.dart \
  test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "test: add mixed tool success and failure scenario"
```

### Task 9: 落地真实文件工具场景

**Files:**
- Modify: `test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_responses_test.dart`

- [ ] **Step 1: 写 failing 场景测试**

```dart
test(
  'real workspace file scenario uses persisted file tools without fake replacements',
  () async {
    final harness = await ChatSendLiveTestHarness.bootstrap(
      providerId: 'minimax-openai-chat-completions',
    );
    await harness.runScenario(buildRealWorkspaceFileOpsScenario());
    final state = await harness.snapshotState();
    expectStepSequence(state, containsToolNames: ['Read', 'Write']);
    await harness.dispose();
  },
  tags: const ['live-headless-agent'],
);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `LIVE_LLM_PROVIDER_IDS=minimax-openai-chat-completions fvm flutter test test/integration/chat_send_live/chat_send_live_chat_completions_test.dart --plain-name "real workspace file scenario uses persisted file tools without fake replacements"`

Expected: FAIL

- [ ] **Step 3: 实现场景与真实目录断言**

实现内容：

- 构造工作目录
- 提供提示词让模型触发真实文件工具
- 断言真实文件内容发生预期结构变化
- 断言 step / event ledger 保持一致

- [ ] **Step 4: 运行测试确认通过**

Run: `LIVE_LLM_PROVIDER_IDS=minimax-openai-chat-completions fvm flutter test test/integration/chat_send_live/chat_send_live_chat_completions_test.dart --plain-name "real workspace file scenario uses persisted file tools without fake replacements"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart \
  test/integration/chat_send_live/chat_send_live_chat_completions_test.dart \
  test/integration/chat_send_live/chat_send_live_responses_test.dart
git commit -m "test: add real workspace file tool scenario"
```

### Task 10: 落地三类 style 的固定测试入口

**Files:**
- Modify: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_responses_test.dart`
- Modify: `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`

- [ ] **Step 1: 写 failing test，验证同一 scenario 可映射多 style**

```dart
test('provider matrix maps one scenario to multiple styles', () {
  final scenario = buildNewsMultiToolScenario();
  expect(
    scenario.providerTargets.map((t) => t.style).toSet().length,
    greaterThan(1),
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart --plain-name "provider matrix maps one scenario to multiple styles"`

Expected: FAIL

- [ ] **Step 3: 实现三类 style 测试入口**

实现内容：

- Anthropic style 文件
- Responses style 文件
- Chat Completions style 文件
- 统一过滤 provider target

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_send_live/chat_send_live_anthropic_test.dart \
  test/integration/chat_send_live/chat_send_live_responses_test.dart \
  test/integration/chat_send_live/chat_send_live_chat_completions_test.dart
git commit -m "test: split headless live scenarios by api style"
```

### Task 11: 新增运行脚本与 style 过滤策略

**Files:**
- Create: `scripts/run_headless_live_integration_tests.sh`
- Modify: `AGENTS.md`
- Modify: `README.md`

- [ ] **Step 1: 写 failing 脚本验证用例**

```bash
bash scripts/run_headless_live_integration_tests.sh anthropic
```

Expected: FAIL，脚本不存在

- [ ] **Step 2: 实现脚本**

脚本要求：

- 接受 style / provider / scenario 过滤参数
- 默认仅运行被选 style
- 支持 `all` 跑三类 style 全集
- 打印 provider 与 scenario 组合

- [ ] **Step 3: 更新文档**

更新内容：

- `AGENTS.md`
  - 新增 headless live integration 命令与运行策略
- `README.md`
  - 新增测试分层说明与示例命令

- [ ] **Step 4: 运行脚本验证**

Run:

```bash
bash scripts/run_headless_live_integration_tests.sh anthropic
bash scripts/run_headless_live_integration_tests.sh all
```

Expected:

- 第一个命令只跑 Anthropic style
- 第二个命令跑三类 style 固定全集

- [ ] **Step 5: 提交**

```bash
git add scripts/run_headless_live_integration_tests.sh AGENTS.md README.md
git commit -m "docs: add headless live integration run workflow"
```

### Task 12: 文档收口与架构对齐

**Files:**
- Modify: `docs/architecture/agent-loop-boundaries-and-decoupling.md`
- Modify: `docs/superpowers/specs/2026-04-28-chat-send-coordinator-headless-live-integration-design.md`
- Test: relevant targeted test commands from previous tasks

- [ ] **Step 1: 补充架构文档中的测试层定位**

明确：

- 单元 / 契约测试
- headless live integration
- UI/E2E

三层职责差异。

- [ ] **Step 2: 回写 spec 中已实现的具体入口与文件**

避免 spec/plan 漂移。

- [ ] **Step 3: 运行最小回归集**

Run:

```bash
fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart
fvm flutter test test/integration/chat_send_live/chat_send_live_responses_test.dart
fvm flutter test test/integration/chat_send_live/chat_send_live_chat_completions_test.dart
```

Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add docs/architecture/agent-loop-boundaries-and-decoupling.md \
  docs/superpowers/specs/2026-04-28-chat-send-coordinator-headless-live-integration-design.md \
  docs/superpowers/plans/2026-04-28-chat-send-coordinator-headless-live-integration-implementation-plan.md
git commit -m "docs: align headless live integration architecture"
```

## 推荐执行顺序

1. Task 1-3：先把 harness、scenario schema、provider matrix 打底
2. Task 4-5：再补 fixture builder 与断言 helpers
3. Task 6-9：按高风险顺序落首批 scenario
4. Task 10-11：最后接 style 入口和运行脚本
5. Task 12：收口文档与最小回归

## 最小首批回归命令

```bash
LIVE_LLM_PROVIDER_IDS=deepseek-anthropic \
  fvm flutter test test/integration/chat_send_live/chat_send_live_anthropic_test.dart

LIVE_LLM_PROVIDER_IDS=beehears-responses \
  fvm flutter test test/integration/chat_send_live/chat_send_live_responses_test.dart

LIVE_LLM_PROVIDER_IDS=minimax-openai-chat-completions \
  fvm flutter test test/integration/chat_send_live/chat_send_live_chat_completions_test.dart
```

## 扩展约束

- 不要把 case 资产按 provider 复制三份
- 不要把最终 assistant 文本写成脆弱的逐字断言
- 不要为了测试方便引入新的正式架构复杂度
- 不要默认把所有工具都 fake 掉
- 不要把 `flutter test` 默认依赖外部网络

## 完成定义

完成本计划后，仓库应具备：

1. 可复用的 `ChatSendCoordinator` headless live integration harness
2. `ScenarioCase + ProviderMatrix` 统一场景模型
3. 真实 test DB 与真实大部分工具支持
4. 至少四个高风险真实场景
5. Anthropic / Responses / Chat Completions 三类 style 的独立测试入口
6. 默认 style 过滤与全集回归脚本
