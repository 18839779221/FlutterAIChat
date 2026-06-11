# Summary-Only 自动压缩续跑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前 session compaction 升级为“统一预算口径 + summary-only 历史重启 + 活跃 turn 中途自动压缩并自动续跑”的机制，解决当前 turn 工具结果膨胀无法自救、以及 UI 百分比与真实触发条件不一致的问题。

**Architecture:** 先统一 `effectiveInputBudget`、`triggerTokens` 和 UI 主百分比的预算语义，再升级 `SessionSummaryService` 为 Claude 风格 continuation summary prompt，然后把 `SessionContextSnapshot` 从 turn 边界扩展到 event 边界，最后在 `TurnHarness` 中加入 active-turn auto-compaction restart。压缩后的 continuation turn 只依赖新的 snapshot summary，不保留 `messagesToKeep`，也不引入 synthetic “continue” user message。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、flutter_test、sqflite、现有 session/turn/transcript 架构。

---

## 文件地图

**新增**

- Create: `test/services/session_context_service_active_turn_compaction_test.dart`
- Create: `test/services/turn_harness_auto_compaction_restart_test.dart`

**修改**

- Modify: `lib/models/session/model_budget_profile.dart`
- Modify: `lib/models/session/context_compaction_config.dart`
- Modify: `lib/models/session/session_context_snapshot.dart`
- Modify: `lib/models/session/context_window_snapshot.dart`
- Modify: `lib/services/model_budget_registry.dart`
- Modify: `lib/services/session_token_budget_service.dart`
- Modify: `lib/services/session_summary_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/session_context_inspector_service.dart`
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/repositories/session_context_snapshot_repository.dart`
- Modify: `lib/widgets/context_window/context_window_usage_indicator.dart`
- Modify: `lib/widgets/context_window/context_window_usage_color.dart`
- Modify: `lib/widgets/context_window/context_window_bottom_sheet.dart`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `test/services/session_token_budget_service_test.dart`
- Modify: `test/services/session_summary_service_test.dart`
- Modify: `test/services/session_context_service_test.dart`
- Modify: `test/services/session_context_inspector_service_test.dart`
- Modify: `test/repositories/session_context_snapshot_repository_test.dart`
- Modify: `test/widgets/context_window/context_window_usage_indicator_test.dart`
- Modify: `test/widgets/context_window/context_window_usage_color_test.dart`
- Modify: `test/widgets/context_window/context_window_bottom_sheet_test.dart`

## Task 1: 统一预算口径为 `effectiveInputBudget + triggerTokens`

**Files:**
- Modify: `lib/models/session/model_budget_profile.dart`
- Modify: `lib/models/session/context_compaction_config.dart`
- Modify: `lib/services/model_budget_registry.dart`
- Modify: `lib/services/session_token_budget_service.dart`
- Test: `test/services/session_token_budget_service_test.dart`

- [ ] **Step 1: 先写失败测试，覆盖 provider input cap 与 trigger tokens**

```dart
test('uses smaller provider input cap when deriving effective input budget', () {
  final service = SessionTokenBudgetService(
    modelBudgetRegistry: ModelBudgetRegistry(
      profiles: {
        'test-model': const ModelBudgetProfile(
          modelId: 'test-model',
          maxContextTokens: 1000,
          providerInputCap: 700,
          reservedOutputTokens: 100,
          reasoningReserveTokens: 50,
          safetyMarginTokens: 50,
          compactionConfig: ContextCompactionConfig(
            autoCompactBufferTokens: 80,
          ),
        ),
      },
    ),
  );

  final result = service.evaluatePlannerBudget(
    modelName: 'test-model',
    fixedPrefixTokens: 200,
    summaryTokens: 100,
    recentTurnsTokens: 60,
    currentTurnTokens: 40,
    toolSchemaTokens: 20,
  );

  expect(result.effectiveInputBudget, 500);
  expect(result.autoCompactTriggerTokens, 420);
  expect(result.totalInputTokens, 420);
  expect(result.shouldCompact, isTrue);
});
```

- [ ] **Step 2: 运行聚焦测试确认当前接口不足**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: FAIL，原因应是当前还没有 `providerInputCap`、`toolSchemaTokens`、`effectiveInputBudget` 或 `autoCompactTriggerTokens`。

- [ ] **Step 3: 扩展预算模型**

在 `ModelBudgetProfile` 增加：

- `providerInputCap`
- `effectiveInputBudget` getter

在 `ContextCompactionConfig` 增加：

- `autoCompactBufferTokens`

保留原有 ratio 字段仅作兼容过渡，但新逻辑不再以 ratio 作为正式触发器。

- [ ] **Step 4: 重构 `SessionPlannerBudgetEvaluation`**

结果对象至少补齐：

- `effectiveInputBudget`
- `toolSchemaTokens`
- `autoCompactTriggerTokens`
- `plannerInputUsageRatio`
- `totalWindowUsageRatio`
- `effectiveInputUsageRatio`

并将 `shouldCompact` 切换为：

```text
totalInputTokens >= autoCompactTriggerTokens
```

- [ ] **Step 5: 最小改动接入 registry 默认值**

先只在 `ModelBudgetRegistry` 内提供 family 默认值，不在本任务引入额外运行时配置来源。`gpt` / `claude` / `gemini` 仍先按当前项目安全预算默认值配置。

- [ ] **Step 6: 跑预算测试到绿**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/models/session/model_budget_profile.dart lib/models/session/context_compaction_config.dart lib/services/model_budget_registry.dart lib/services/session_token_budget_service.dart test/services/session_token_budget_service_test.dart
git commit -m "refactor: unify compaction budget semantics"
```

## Task 2: 升级 summary prompt 为 Claude 风格 continuation summary

**Files:**
- Modify: `lib/services/session_summary_service.dart`
- Test: `test/services/session_summary_service_test.dart`

- [ ] **Step 1: 先写失败测试，锁定 prompt 结构**

```dart
test('uses claude-style continuation summary prompt sections', () async {
  final service = SessionSummaryService(
    summaryGenerator: (messages) async {
      final prompt = messages.first.text;
      expect(prompt, contains('<analysis>'));
      expect(prompt, contains('<summary>'));
      expect(prompt, contains('Primary Request and Intent'));
      expect(prompt, contains('All user messages'));
      expect(prompt, contains('Context for Continuing Work'));
      return '<summary>ok</summary>';
    },
  );

  await service.summarizeHistory(
    previousSummary: 'old summary',
    historicalMessages: [
      ChatMessage(text: '继续处理当前任务', role: MessageRole.user),
    ],
  );
});
```

- [ ] **Step 2: 运行 summary 测试确认当前 prompt 不符合**

Run: `fvm flutter test test/services/session_summary_service_test.dart`

Expected: FAIL，因为当前 prompt 仍是早期固定中文栏目模板。

- [ ] **Step 3: 重写 summary instruction prompt**

要求：

- 保留 Claude 风格的 `<analysis>` / `<summary>` 约束
- 栏目尽量复用 Claude 原模板
- 只在 “Files and Code Sections” 节补一句非代码任务适配说明

不要做：

- 结构化解析
- DTO 存储
- prompt 中引入 `messagesToKeep` 语义

- [ ] **Step 4: 让 service 只提取 `<summary>` 内容**

如果 generator 返回 `<analysis>...</analysis><summary>...</summary>`，正式存储只保留 `<summary>` 体；如果没有标签，回退到 trim 后全文，避免 summary generator 差异导致崩溃。

- [ ] **Step 5: 补失败测试，覆盖 previous summary 滚动与标签剥离**

新增测试验证：

- `previousSummary` 仍会作为 system message 参与下一轮 summary
- `<analysis>` 不会进入 `summaryText`

- [ ] **Step 6: 跑 summary 测试到绿**

Run: `fvm flutter test test/services/session_summary_service_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_summary_service.dart test/services/session_summary_service_test.dart
git commit -m "refactor: adopt continuation summary prompt"
```

## Task 3: 扩展 snapshot 到 event 级边界

**Files:**
- Modify: `lib/models/session/session_context_snapshot.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/repositories/session_context_snapshot_repository.dart`
- Modify: `lib/services/session_context_service.dart`
- Test: `test/repositories/session_context_snapshot_repository_test.dart`
- Test: `test/services/session_context_service_test.dart`
- Test: `test/services/session_context_service_active_turn_compaction_test.dart`

- [ ] **Step 1: 先写 repository 失败测试，覆盖 `coveredUntilEventId`**

```dart
test('persists partial-turn compaction boundary with coveredUntilEventId', () async {
  final id = await repository.upsertLatest(
    SessionContextSnapshot(
      groupId: groupId,
      summaryText: 'summary',
      coveredUntilTurnId: 12,
      coveredUntilEventId: 1205,
      estimatedTokens: 180,
    ),
  );

  final snapshot = await repository.getLatestByGroup(groupId);

  expect(id, greaterThan(0));
  expect(snapshot!.coveredUntilEventId, 1205);
});
```

- [ ] **Step 2: 运行 repository 测试确认数据库 schema 还不支持**

Run: `fvm flutter test test/repositories/session_context_snapshot_repository_test.dart`

Expected: FAIL，原因是 model / schema 缺字段。

- [ ] **Step 3: 增加 snapshot 字段与数据库迁移**

在 `session_context_snapshots` 表增加：

- `covered_until_event_id INTEGER`

要求：

- 新库直接建带字段的表
- 老库升级路径补列
- repository / model `toMap/fromMap/copyWith` 全量同步

- [ ] **Step 4: 先写 context service 失败测试，覆盖 active-turn 后缀保留**

```dart
test('keeps only post-boundary suffix from partially compacted current turn', () async {
  final snapshot = SessionContextSnapshot(
    groupId: groupId,
    summaryText: 'summary',
    coveredUntilTurnId: currentTurnId,
    coveredUntilEventId: toolResultEventId,
    estimatedTokens: 50,
  );
  await snapshotRepository.upsertLatest(snapshot);

  final state = await service.buildPlannerContextState(
    groupId: groupId,
    currentTurnId: currentTurnId,
    currentTurnTranscript: transcript,
    config: _chatConfig(),
  );

  final joined = state.currentTurnMessages.map((m) => m.text).join('\n');
  expect(joined, isNot(contains('old tool result before compaction')));
  expect(joined, contains('new event after compaction'));
});
```

- [ ] **Step 5: 修改 `SessionContextService` 读取规则**

要求：

- `coveredUntilTurnId` 之前的 whole turns 跳过
- 若当前 turn 命中 `coveredUntilTurnId` 且 `coveredUntilEventId != null`，只投影 event 后缀
- 手动压缩仍然写 `coveredUntilEventId = null`

- [ ] **Step 6: 新增 `session_context_service_active_turn_compaction_test.dart`**

这里专门测：

- active turn 中多事件被切分后的 planner context 是否只保留后缀
- legacy `coveredUntilEventId == null` 行为不回归

- [ ] **Step 7: 跑 snapshot/context service 相关测试**

Run:

- `fvm flutter test test/repositories/session_context_snapshot_repository_test.dart`
- `fvm flutter test test/services/session_context_service_test.dart`
- `fvm flutter test test/services/session_context_service_active_turn_compaction_test.dart`

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/models/session/session_context_snapshot.dart lib/database/database_helper.dart lib/repositories/session_context_snapshot_repository.dart lib/services/session_context_service.dart test/repositories/session_context_snapshot_repository_test.dart test/services/session_context_service_test.dart test/services/session_context_service_active_turn_compaction_test.dart
git commit -m "feat: support event-level compaction boundaries"
```

## Task 4: 在 `SessionContextService` 中补齐 active-turn compaction 计划能力

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/session_context_service_active_turn_compaction_test.dart`

- [ ] **Step 1: 先写失败测试，覆盖“当前 turn 内工具结果导致应触发 active-turn compaction”**

```dart
test('detects active-turn compaction candidate when current transcript exceeds trigger', () async {
  final plan = await service.planActiveTurnCompaction(
    groupId: groupId,
    currentTurnId: currentTurnId,
    currentTurnTranscript: transcript,
    config: _chatConfig(),
    boundaryEventId: toolResultEventId,
  );

  expect(plan, isNotNull);
  expect(plan!.coveredUntilTurnId, currentTurnId);
  expect(plan.coveredUntilEventId, toolResultEventId);
  expect(plan.continuationSummaryText, contains('Current Work'));
});
```

- [ ] **Step 2: 运行新测试确认缺少 planning API**

Run: `fvm flutter test test/services/session_context_service_active_turn_compaction_test.dart`

Expected: FAIL。

- [ ] **Step 3: 给 `SessionContextService` 增加显式 active-turn compaction 入口**

不要把逻辑完全塞进 `buildPlannerContextState()`。新增一个明确 API，例如：

- `planActiveTurnCompaction(...)`
- `applyActiveTurnCompaction(...)`

职责拆分：

- `plan...` 负责选边界、汇总要压缩的历史和当前 turn 前缀、生成 summary
- `apply...` 负责写 snapshot、落 `contextCompacted` 边界、返回 continuation 所需信息

- [ ] **Step 4: 只让 compaction source 覆盖到 boundary event 为止**

确保被压入 summary 的内容包括：

- snapshot 之后所有未压缩 completed turns
- 当前 turn 中直到 `boundaryEventId` 为止的 planner-visible transcript 前缀

不包括：

- 边界之后的新事件后缀

- [ ] **Step 5: 在 apply 结果里返回 continuation 所需最小状态**

至少包含：

- 新 snapshot
- `coveredUntilTurnId`
- `coveredUntilEventId`
- 新 continuation turn 的 `userInput`
- 是否已写入 boundary event

后续 `TurnHarness` 直接消费，不再自己反推。

- [ ] **Step 6: 跑 active-turn compaction service 测试到绿**

Run: `fvm flutter test test/services/session_context_service_active_turn_compaction_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_context_service.dart test/services/session_context_service_active_turn_compaction_test.dart
git commit -m "feat: add active-turn compaction planning"
```

## Task 5: 在 `TurnHarness` 中实现自动压缩重启与自动续跑

**Files:**
- Modify: `lib/services/turn_harness.dart`
- Test: `test/services/turn_harness_auto_compaction_restart_test.dart`
- Test: `test/services/turn_harness_test.dart`

- [ ] **Step 1: 先写失败测试，覆盖 active-turn tool loop 自动压缩续跑**

```dart
test('auto-compacts active turn and continues in a new continuation turn', () async {
  final emitted = await harness.runTurn(
    turn: turn,
    config: ChatConfig(systemPrompt: ''),
  ).toList();

  expect(
    emitted.map((e) => e.eventType),
    contains(ChatEventType.contextCompacted),
  );

  final turns = await turnRepository.getTurnsByGroup(turn.groupId);
  expect(turns.length, 2);
  expect(turns.first.stopReason, 'auto_compacted_continue');
  expect(turns.last.status, ChatTurnStatus.completed);
});
```

- [ ] **Step 2: 运行 harness 聚焦测试确认当前 loop 不支持 restart**

Run:

- `fvm flutter test test/services/turn_harness_auto_compaction_restart_test.dart`

Expected: FAIL。

- [ ] **Step 3: 在 `TurnHarness` 增加统一检查点 helper**

新增一个集中方法，例如：

- `_maybeAutoCompactAndRestart(...)`

检查点调用位置：

- 新 turn 首次 planner 前
- 每次 planner 前
- `toolResult` / `toolError` / `userInteractionResult` 落地后、下一次 planner 之前

- [ ] **Step 4: continuation turn 创建规则**

要求：

- 同 group
- 继承 provider style / model / runtime context
- 不新增新的用户消息 event
- 不新增 synthetic “continue” message
- continuation 只靠新 snapshot summary 继续

- [ ] **Step 5: 旧 turn 收口规则**

要求：

- 旧 turn 追加 `contextCompacted`
- 标记 `stopReason = auto_compacted_continue`
- 不标 failed

必要时在 `providerStateJson` 里加一个轻量 marker，但不要新增复杂状态机。

- [ ] **Step 6: 跑 harness 测试**

Run:

- `fvm flutter test test/services/turn_harness_auto_compaction_restart_test.dart`
- `fvm flutter test test/services/turn_harness_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/turn_harness.dart test/services/turn_harness_auto_compaction_restart_test.dart test/services/turn_harness_test.dart
git commit -m "feat: restart active turns after auto compaction"
```

## Task 6: 同步 inspector / context window UI 到新预算口径

**Files:**
- Modify: `lib/models/session/context_window_snapshot.dart`
- Modify: `lib/services/session_context_inspector_service.dart`
- Modify: `lib/widgets/context_window/context_window_usage_indicator.dart`
- Modify: `lib/widgets/context_window/context_window_usage_color.dart`
- Modify: `lib/widgets/context_window/context_window_bottom_sheet.dart`
- Test: `test/services/session_context_inspector_service_test.dart`
- Test: `test/widgets/context_window/context_window_usage_indicator_test.dart`
- Test: `test/widgets/context_window/context_window_usage_color_test.dart`
- Test: `test/widgets/context_window/context_window_bottom_sheet_test.dart`

- [ ] **Step 1: 先写失败测试，锁定主指标改为 planner input usage**

```dart
testWidgets('indicator uses planner input usage ratio as visible percentage', (tester) async {
  final snapshot = ContextWindowSnapshot(
    modelName: 'gpt-test',
    maxContextTokens: 128000,
    effectiveInputBudget: 104000,
    autoCompactTriggerTokens: 91000,
    totalEstimatedInputTokens: 45500,
    plannerInputUsageRatio: 0.5,
    totalWindowUsageRatio: 0.35,
    effectiveInputUsageRatio: 0.4375,
    didCompactHistory: false,
    recentCompletedTurnCount: 0,
    segments: const [],
  );

  await tester.pumpWidget(_host(ContextWindowUsageIndicator(snapshot: snapshot, onTap: () {})));
  expect(find.text('50%'), findsOneWidget);
});
```

- [ ] **Step 2: 运行 UI/inspector 测试确认当前字段模型不足**

Run:

- `fvm flutter test test/services/session_context_inspector_service_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_usage_indicator_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_usage_color_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: FAIL。

- [ ] **Step 3: 扩展 `ContextWindowSnapshot`**

新增字段至少包括：

- `effectiveInputBudget`
- `autoCompactTriggerTokens`
- `plannerInputUsageRatio`
- `effectiveInputUsageRatio`
- `snapshotCoveredUntilEventId`

保留 `totalWindowUsageRatio` 作为诊断值，不再作为主入口指标。

- [ ] **Step 4: 修改 inspector 计算逻辑**

要求：

- 主 ratio 按 `estimatedPlannerInputTokens / autoCompactTriggerTokens`
- 继续产出 total/effective 两个诊断 ratio
- segment 明细仍区分 planner-visible 与 reserves

- [ ] **Step 5: 修改 UI**

要求：

- indicator 进度和颜色阈值都使用 `plannerInputUsageRatio`
- bottom sheet 顶部 summary card 同时展示：
  - planner input
  - total window
  - effective input budget
  - trigger tokens

- [ ] **Step 6: 跑 UI/inspector 测试到绿**

Run:

- `fvm flutter test test/services/session_context_inspector_service_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_usage_indicator_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_usage_color_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/models/session/context_window_snapshot.dart lib/services/session_context_inspector_service.dart lib/widgets/context_window/context_window_usage_indicator.dart lib/widgets/context_window/context_window_usage_color.dart lib/widgets/context_window/context_window_bottom_sheet.dart test/services/session_context_inspector_service_test.dart test/widgets/context_window/context_window_usage_indicator_test.dart test/widgets/context_window/context_window_usage_color_test.dart test/widgets/context_window/context_window_bottom_sheet_test.dart
git commit -m "refactor: align context window ui with compaction trigger"
```

## Task 7: 更新架构文档并做串行回归

**Files:**
- Modify: `docs/architecture/session-context-management.md`

- [ ] **Step 1: 更新 architecture 文档**

补齐：

- `effectiveInputBudget`
- `autoCompactTriggerTokens`
- active-turn event boundary
- summary-only continuation turn
- auto-compaction 检查点

- [ ] **Step 2: 串行运行本轮核心测试集**

Run:

- `fvm flutter test test/services/session_token_budget_service_test.dart`
- `fvm flutter test test/services/session_summary_service_test.dart`
- `fvm flutter test test/repositories/session_context_snapshot_repository_test.dart`
- `fvm flutter test test/services/session_context_service_test.dart`
- `fvm flutter test test/services/session_context_service_active_turn_compaction_test.dart`
- `fvm flutter test test/services/turn_harness_auto_compaction_restart_test.dart`
- `fvm flutter test test/services/turn_harness_test.dart`
- `fvm flutter test test/services/session_context_inspector_service_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_usage_indicator_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_usage_color_test.dart`
- `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: 全部 PASS。

- [ ] **Step 3: 视时间补一条 headless integration 回归**

优先复用现有 live/integration harness，不要求默认联网。若本地难以稳定模拟 repeated `web_search`，至少在 test plan 中记录手动验证脚本与预期。

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/session-context-management.md
git commit -m "docs: document summary-only auto compaction restart"
```

## Review Note

本计划原本按 `writing-plans` 技能建议应再派发 plan reviewer 子代理复查，但本轮未获得用户关于子代理/委派的明确许可，因此保持本地自检，不额外使用多代理工具。
