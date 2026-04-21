# Session 上下文管理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为同一 `group` 建立完整的 Session 级上下文管理，让多轮消息、工具结果、交互问答能稳定进入下一轮 planner，并在接近模型上下文上限时按 token budget 自动压缩为摘要快照。

**Architecture:** 保留 `messages` 作为 UI 时间线、`chat_turns/chat_turn_steps/chat_events` 作为单轮 ledger，在其上新增 `SessionContextService`、`SessionContextProjector`、`SessionTokenBudgetService`、`SessionSummaryService` 和 `session_context_snapshots` 存储层。planner 输入收敛为“历史摘要 + 最近工作集 + 当前 turn transcript”，旧 `context_strategies.dart` 体系直接删除，不做兼容并存。

**Tech Stack:** Flutter 3.29.2（优先 `fvm flutter`）、Dart、sqflite、flutter_test、现有 agent loop / repository / provider 架构。

---

## 文件地图

**新增服务与模型**

- Create: `lib/models/session/session_context_snapshot.dart`
- Create: `lib/services/session_context_service.dart`
- Create: `lib/services/session_context_projector.dart`
- Create: `lib/services/session_token_budget_service.dart`
- Create: `lib/services/session_summary_service.dart`
- Create: `lib/repositories/session_context_snapshot_repository.dart`

**存储与数据层**

- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/storage/web_chat_storage.dart`

**主链路接入**

- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `lib/services/transcript_builder_service.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`

**旧上下文策略清理**

- Delete: `lib/models/context/context_strategies.dart`
- Delete: `lib/models/context/message_context_strategy.dart`

**测试**

- Create: `test/services/session_context_service_test.dart`
- Create: `test/services/session_context_projector_test.dart`
- Create: `test/services/session_token_budget_service_test.dart`
- Create: `test/services/session_summary_service_test.dart`
- Create: `test/repositories/session_context_snapshot_repository_test.dart`
- Modify: `test/services/turn_harness_test.dart`
- Modify: `test/services/agent_planner_service_test.dart`
- Modify: `test/providers/chat_dependency_providers_test.dart`
- Modify: `test/database/database_helper_test.dart`

**文档**

- Modify: `README.md`
- Modify: `AGENTS.md`
- Create: `docs/architecture/session-context-management.md`

## 任务 1：建立 Session Context Snapshot 数据模型与存储接口

**Files:**
- Create: `lib/models/session/session_context_snapshot.dart`
- Create: `lib/repositories/session_context_snapshot_repository.dart`
- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/storage/web_chat_storage.dart`
- Test: `test/repositories/session_context_snapshot_repository_test.dart`
- Test: `test/database/database_helper_test.dart`

- [ ] **Step 1: 先写 snapshot repository 失败测试**

```dart
test('can persist and reload latest session context snapshot by group', () async {
  final storage = DatabaseHelper(databaseName: 'session_context_snapshot_test.db');
  final repository = SessionContextSnapshotRepository(storage);
  final groupId = await storage.insertGroup(_group('Session Context'));

  final id = await repository.upsertLatest(
    SessionContextSnapshot(
      groupId: groupId,
      summaryText: '当前目标：实现 Session 上下文管理',
      coveredUntilTurnId: 12,
      estimatedTokens: 180,
    ),
  );

  final snapshot = await repository.getLatestByGroup(groupId);

  expect(id, greaterThan(0));
  expect(snapshot!.coveredUntilTurnId, 12);
  expect(snapshot.summaryText, contains('Session 上下文管理'));
});
```

- [ ] **Step 2: 运行存储层聚焦测试，确认当前缺失表与接口**

Run: `fvm flutter test test/repositories/session_context_snapshot_repository_test.dart test/database/database_helper_test.dart`

Expected: FAIL，提示缺少 `SessionContextSnapshot` 类型、repository、`chat_storage` 接口或 `session_context_snapshots` 表。

- [ ] **Step 3: 定义 snapshot 模型**

在 `lib/models/session/session_context_snapshot.dart` 中新增模型，字段至少包含：

- `id`
- `groupId`
- `summaryText`
- `coveredUntilTurnId`
- `estimatedTokens`
- `createdAt`
- `updatedAt`

为字段添加简洁注释，说明它们与 Session 上下文边界的关系。

- [ ] **Step 4: 扩展 ChatStorage 接口**

在 `lib/storage/chat_storage.dart` 中新增 snapshot CRUD：

- `insertSessionContextSnapshot`
- `updateSessionContextSnapshot`
- `getLatestSessionContextSnapshotByGroup`

保持命名清晰，不要把 snapshot 接口混到 message 或 turn 接口组里。

- [ ] **Step 5: 实现数据库建表与迁移**

在 `lib/database/database_helper.dart` 中：

- 新增 `session_context_snapshots` 建表 SQL
- 提升数据库版本
- 在升级路径中补迁移
- 实现对应 CRUD

表结构至少包含：

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `group_id INTEGER NOT NULL`
- `summary_text TEXT NOT NULL`
- `covered_until_turn_id INTEGER NOT NULL`
- `estimated_tokens INTEGER NOT NULL DEFAULT 0`
- `created_at INTEGER NOT NULL`
- `updated_at INTEGER NOT NULL`

- [ ] **Step 6: 为 Web 存储补齐实现**

在 `lib/storage/web_chat_storage.dart` 中补齐相同接口；实现可以先用现有内存/Map 风格，但字段语义必须与原生存储一致。

- [ ] **Step 7: 实现 SessionContextSnapshotRepository**

在 repository 中封装：

- 读取 group 最近快照
- 创建首个快照
- 更新已有快照

第一版使用“每个 group 只关心最近有效快照”的读写语义。

- [ ] **Step 8: 重新运行存储层测试**

Run: `fvm flutter test test/repositories/session_context_snapshot_repository_test.dart test/database/database_helper_test.dart`

Expected: PASS。

- [ ] **Step 9: Commit**

```bash
git add lib/models/session/session_context_snapshot.dart lib/repositories/session_context_snapshot_repository.dart lib/storage/chat_storage.dart lib/database/database_helper.dart lib/storage/web_chat_storage.dart test/repositories/session_context_snapshot_repository_test.dart test/database/database_helper_test.dart
git commit -m "feat: add session context snapshot storage"
```

## 任务 2：实现 SessionContextProjector，把历史事实投影为模型可见上下文

**Files:**
- Create: `lib/services/session_context_projector.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/services/transcript_builder_service.dart`
- Test: `test/services/session_context_projector_test.dart`

- [ ] **Step 1: 先写投影规则失败测试**

```dart
test('projects tool result and user interaction result into compact context messages', () {
  final projector = SessionContextProjector();

  final messages = projector.projectEventsToContext([
    _toolResultEvent('以下是工具 `read` 的执行结果，请结合这些信息回答用户。\\n结果摘要：数据库版本是 9'),
    _userInteractionResultEvent('用户回答：目标平台仅 Android'),
    _toolCallEvent('准备执行工具：read'),
  ]);

  expect(messages.map((m) => m.text).join('\n'), contains('数据库版本是 9'));
  expect(messages.map((m) => m.text).join('\n'), contains('目标平台仅 Android'));
  expect(messages.map((m) => m.text).join('\n'), isNot(contains('准备执行工具：read')));
});
```

- [ ] **Step 2: 运行 projector 聚焦测试**

Run: `fvm flutter test test/services/session_context_projector_test.dart`

Expected: FAIL，因为当前没有 projector，或 `chat_event` 到上下文消息的投影仍混杂在 transcript 逻辑里。

- [ ] **Step 3: 实现 SessionContextProjector**

新增对以下来源的投影方法：

- 普通 `ChatMessage` 历史消息投影
- `ChatEvent` 列表投影
- snapshot 文本投影

并落实规则：

- 保留 `userMessage`
- 保留 `finalAnswer`
- 投影 `toolResult` / `toolError` / `assistantQuestionPrompt` / `userInteractionResult`
- 过滤 `assistantToolCall` / `toolExecutionStarted` / `turnStatus`

- [ ] **Step 4: 精简 TranscriptBuilderService 的上下文职责**

如 `TranscriptBuilderService` 中存在“顺手构造模型消息”的旧逻辑，把纯投影职责迁移到 `SessionContextProjector`，保留它作为 turn transcript 读取与 final-answer 辅助服务。

- [ ] **Step 5: 为投影文本格式补稳定约束**

确保投影文本：

- 不回灌原始 payload JSON
- 保留结论、限制、失败原因
- 用短格式表达“发生了什么 / 学到了什么”

- [ ] **Step 6: 重新运行 projector 测试**

Run: `fvm flutter test test/services/session_context_projector_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_context_projector.dart lib/models/chat_event.dart lib/services/transcript_builder_service.dart test/services/session_context_projector_test.dart
git commit -m "feat: add session context projector"
```

## 任务 3：实现 SessionTokenBudgetService，统一 token 预算与压缩触发口径

**Files:**
- Create: `lib/services/session_token_budget_service.dart`
- Modify: `lib/services/chat_service.dart`
- Test: `test/services/session_token_budget_service_test.dart`

- [ ] **Step 1: 先写 token budget 失败测试**

```dart
test('signals compression when estimated input reaches pressure threshold', () {
  final service = SessionTokenBudgetService(
    modelBudgetResolver: (_) => const SessionModelBudget(
      maxContextTokens: 1000,
      reservedOutputTokens: 200,
      safetyMarginTokens: 100,
      pressureThreshold: 0.85,
    ),
  );

  final result = service.evaluate(
    modelName: 'test-model',
    systemPromptTokens: 120,
    toolSchemaTokens: 80,
    candidateContextTokens: 420,
    currentTurnTokens: 90,
  );

  expect(result.shouldCompress, true);
});
```

- [ ] **Step 2: 运行预算测试**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: FAIL，因为当前没有统一预算服务，也没有模型级预算解析入口。

- [ ] **Step 3: 定义预算模型与结果对象**

在 `SessionTokenBudgetService` 中定义：

- `SessionModelBudget`
- `SessionBudgetEvaluation`

字段至少包含：

- `inputBudget`
- `estimatedInputTokens`
- `pressureRatio`
- `shouldCompress`

- [ ] **Step 4: 选择 token 估算来源**

第一版可以采用与旧 `MessageContextStrategy.estimateTokens()` 同等级的近似估算思路，但迁移到新服务中，不再保留旧策略文件。

要求：

- 支持 system prompt 文本估算
- 支持工具 schema 描述估算
- 支持上下文消息文本估算

- [ ] **Step 5: 为当前模型预留动态预算入口**

不要写死全局常量。设计一个从当前模型名或 provider 配置解析预算的入口，先允许：

- 有默认值
- 后续可按模型扩展

- [ ] **Step 6: 重新运行预算测试**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_token_budget_service.dart lib/services/chat_service.dart test/services/session_token_budget_service_test.dart
git commit -m "feat: add session token budget service"
```

## 任务 4：实现 SessionSummaryService，生成可复用历史摘要

**Files:**
- Create: `lib/services/session_summary_service.dart`
- Modify: `lib/services/chat_service.dart`
- Test: `test/services/session_summary_service_test.dart`

- [ ] **Step 1: 先写摘要格式失败测试**

```dart
test('builds stable session summary prompt from projected history messages', () async {
  final service = SessionSummaryService(chatService: _fakeChatServiceReturning('''
当前目标：实现 Session 上下文管理
已确认事实：需要按 token budget 自动压缩
未完成事项：接入 TurnHarness
'''));

  final summary = await service.summarize(
    groupId: 1,
    projectedHistory: [
      _userMessage('我们需要支持多轮上下文'),
      _assistantMessage('我会先设计 SessionContextService'),
    ],
  );

  expect(summary.summaryText, contains('当前目标'));
  expect(summary.summaryText, contains('未完成事项'));
});
```

- [ ] **Step 2: 运行摘要测试**

Run: `fvm flutter test test/services/session_summary_service_test.dart`

Expected: FAIL，因为当前没有独立的 session 摘要服务。

- [ ] **Step 3: 实现摘要服务接口**

为 `SessionSummaryService` 提供：

- 输入：需被压缩的投影历史消息
- 输出：结构化摘要文本与估算 token

服务不负责“何时触发”，只负责“给一段历史生成摘要”。

- [ ] **Step 4: 固化摘要栏目**

摘要模板至少要求这些栏目：

- 当前目标
- 已确认事实
- 用户偏好/限制
- 重要工具结论
- 未完成事项
- 风险与下一步

不要让测试只验证“随便有段文本返回”，要验证栏目稳定性。

- [ ] **Step 5: 处理失败与空结果**

当模型返回空字符串或异常时：

- 返回可识别失败结果
- 不写入 snapshot
- 让上层可以安全降级

- [ ] **Step 6: 重新运行摘要测试**

Run: `fvm flutter test test/services/session_summary_service_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_summary_service.dart lib/services/chat_service.dart test/services/session_summary_service_test.dart
git commit -m "feat: add session summary service"
```

## 任务 5：实现 SessionContextService，编排 snapshot、最近工作集和当前 turn transcript

**Files:**
- Create: `lib/services/session_context_service.dart`
- Modify: `lib/repositories/chat_turn_repository.dart`
- Modify: `lib/database/database_helper.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 先写 session context 拼装失败测试**

```dart
test('builds planner messages from snapshot, recent working set, and current turn transcript', () async {
  final service = _buildSessionContextService(
    snapshot: SessionContextSnapshot(
      groupId: 7,
      summaryText: '当前目标：完成 SessionContextService 接入',
      coveredUntilTurnId: 10,
      estimatedTokens: 120,
    ),
    historyMessages: [
      _assistantMessage('最近工作集：TurnHarness 还没接入'),
    ],
    currentTurnEvents: [
      _userMessageEvent('继续，帮我把接入点梳理清楚'),
      _toolResultEvent('结果摘要：TurnHarness 是主入口'),
    ],
  );

  final plannerMessages = await service.buildPlannerMessages(
    groupId: 7,
    currentTurnId: 12,
    currentTurnTranscript: _currentTranscript(),
    config: _chatConfig(),
  );

  expect(plannerMessages.first.text, contains('当前目标'));
  expect(plannerMessages.map((m) => m.text).join('\n'), contains('最近工作集'));
  expect(plannerMessages.last.text, contains('TurnHarness 是主入口'));
});
```

- [ ] **Step 2: 运行 session context 聚焦测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: FAIL，因为当前没有 `SessionContextService` 与跨 turn 组装逻辑。

- [ ] **Step 3: 为 chat turn 历史读取补接口**

若当前 repository / storage 无法按 `groupId` 读取最近已完成 turn，先补最小接口，例如：

- 读取某 group 已完成 turn 列表
- 按 `coveredUntilTurnId` 之后筛选

尽量让这部分在 repository 层完成，不把 SQL 直接堆进 service。

- [ ] **Step 4: 实现 buildPlannerMessages 主流程**

实现顺序：

1. 读当前 group 最新 snapshot
2. 读取 snapshot 边界之后的最近 working set
3. 投影 working set 的消息和事件
4. 投影当前 turn transcript
5. 调用预算服务评估
6. 必要时生成/刷新摘要并重建消息列表

- [ ] **Step 5: 限制 working set 的裁剪单位**

working set 的保留与裁剪必须以：

- 已完成 turn
- 已完成交互闭环

为单位，不允许按单条 event 生切。

- [ ] **Step 6: 处理无 snapshot / 摘要失败降级**

至少覆盖两条降级路径：

- 没有 snapshot：直接用 recent working set + current turn
- 摘要失败：缩短 working set，但不阻塞 planner

- [ ] **Step 7: 重新运行 session context 测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/services/session_context_service.dart lib/repositories/chat_turn_repository.dart lib/database/database_helper.dart test/services/session_context_service_test.dart
git commit -m "feat: build planner context from session history"
```

## 任务 6：把 SessionContextService 接入 TurnHarness 与依赖提供层

**Files:**
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `test/services/turn_harness_test.dart`
- Modify: `test/providers/chat_dependency_providers_test.dart`

- [ ] **Step 1: 先写 TurnHarness 回归失败测试**

```dart
test('planner uses session context messages instead of only current turn transcript', () async {
  final harness = _buildHarnessWithSessionContext(
    plannerDecision: _terminalDecision('好的，我会继续实现'),
  );

  await harness.runTurn(
    turn: _turn(groupId: 5, id: 22, userInput: '继续'),
    config: ChatConfig(useReasoning: false, systemPrompt: ''),
  ).drain();

  expect(_capturedPlannerMessagesText(), contains('历史摘要'));
  expect(_capturedPlannerMessagesText(), contains('最近工作集'));
});
```

- [ ] **Step 2: 运行接入层测试**

Run: `fvm flutter test test/services/turn_harness_test.dart test/providers/chat_dependency_providers_test.dart`

Expected: FAIL，因为 `TurnHarness` 仍只基于当前 turn transcript 调 planner。

- [ ] **Step 3: 在 provider 层注册新服务**

在 `chat_dependency_providers.dart` 中新增：

- `sessionContextProjectorProvider`
- `sessionTokenBudgetServiceProvider`
- `sessionSummaryServiceProvider`
- `sessionContextSnapshotRepositoryProvider`
- `sessionContextServiceProvider`

保持 provider 依赖清晰，不要在 `TurnHarness` 内直接 new 多个服务。

- [ ] **Step 4: 调整 TurnHarness 调 planner 前的消息组装**

将 `_continueTurnLoop()` 中的 planner 输入改成通过 `SessionContextService.buildPlannerMessages(...)` 获取。

要求：

- `AgentPlannerService` 不新增会话拼装职责
- `TurnHarness` 只负责编排，不负责底层投影实现

- [ ] **Step 5: 确认 ChatSendCoordinator 依赖图仍可创建**

必要时调整 `chat_send_coordinator.dart` 读取的新 provider，确保发送主链路不因 provider 缺失而失败。

- [ ] **Step 6: 重新运行接入层测试**

Run: `fvm flutter test test/services/turn_harness_test.dart test/providers/chat_dependency_providers_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/turn_harness.dart lib/providers/chat_dependency_providers.dart lib/controllers/chat_send_coordinator.dart test/services/turn_harness_test.dart test/providers/chat_dependency_providers_test.dart
git commit -m "feat: wire session context into planner loop"
```

## 任务 7：删除旧 context_strategies 体系并清理引用

**Files:**
- Delete: `lib/models/context/context_strategies.dart`
- Delete: `lib/models/context/message_context_strategy.dart`
- Modify: 任何残留引用文件
- Test: 全量 `rg` 检查 + 相关回归测试

- [ ] **Step 1: 查找残留引用**

Run: `rg -n "context_strategies|MessageContextStrategy|FixedCountStrategy|TokenBasedStrategy|SmartSelectionStrategy|HybridStrategy" lib test`

Expected: 列出当前仍引用旧策略的文件。

- [ ] **Step 2: 删除旧文件**

删除：

- `lib/models/context/context_strategies.dart`
- `lib/models/context/message_context_strategy.dart`

- [ ] **Step 3: 修正残留引用与测试**

把仍引用旧上下文策略的代码和测试改到新的 `SessionContext*` 体系；不要留下“旧策略保留但未使用”的死文件。

- [ ] **Step 4: 运行引用检查与聚焦回归**

Run: `rg -n "context_strategies|MessageContextStrategy|FixedCountStrategy|TokenBasedStrategy|SmartSelectionStrategy|HybridStrategy" lib test`

Expected: 无结果。

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/turn_harness_test.dart`

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git rm lib/models/context/context_strategies.dart lib/models/context/message_context_strategy.dart
git add .
git commit -m "refactor: remove legacy context strategy system"
```

## 任务 8：更新文档与架构说明

**Files:**
- Create: `docs/architecture/session-context-management.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 先写架构文档骨架**

在 `docs/architecture/session-context-management.md` 写明：

- Session 定义
- 三层职责边界
- `SessionContextService` 及协作者
- token budget 策略
- snapshot 数据模型
- 投影规则
- 旧上下文策略删除原因

- [ ] **Step 2: 更新 README 能力说明**

补充：

- 项目已支持 Session 级多轮上下文
- 长对话会按 token 预算自动压缩

- [ ] **Step 3: 更新 AGENTS.md**

补充或修正：

- 旧 `context_strategies.dart` 已退役
- 新 Session 上下文主链路入口
- 上下文压缩与 token budget 的约束

- [ ] **Step 4: 自检文档一致性**

Run: `rg -n "context_strategies|SessionContextService|session_context_snapshots|token budget|上下文" README.md AGENTS.md docs/architecture docs/superpowers/specs`

Expected: 新文档之间表述一致，不再暗示旧系统仍在使用。

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/session-context-management.md README.md AGENTS.md
git commit -m "docs: document session context architecture"
```

## 任务 9：执行全量验证并收尾

**Files:**
- Verify only

- [ ] **Step 1: 运行格式与静态检查**

Run: `fvm flutter analyze`

Expected: PASS。

- [ ] **Step 2: 运行核心测试集**

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/session_context_projector_test.dart test/services/session_token_budget_service_test.dart test/services/session_summary_service_test.dart test/repositories/session_context_snapshot_repository_test.dart test/services/turn_harness_test.dart test/providers/chat_dependency_providers_test.dart test/database/database_helper_test.dart`

Expected: PASS。

- [ ] **Step 3: 运行相关回归测试**

Run: `fvm flutter test test/services/agent_planner_service_test.dart`

Expected: PASS，确认新 session 上下文接入没有破坏 planner 主链路。

- [ ] **Step 4: 检查工作区变更**

Run: `git status --short`

Expected: 只包含本次 Session 上下文改造相关文件。

- [ ] **Step 5: 最终提交**

```bash
git add .
git commit -m "feat: add session context management"
```
