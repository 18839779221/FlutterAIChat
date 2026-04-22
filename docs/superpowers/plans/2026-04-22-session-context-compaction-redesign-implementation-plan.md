# Session 上下文压缩重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Session 上下文压缩改造成“预算驱动 + summary 滚动压缩 + recent completed turns 双约束”模型，确保 planner 上下文边界清晰、历史不丢语义、压缩后保持小历史负载。

**Architecture:** 在现有 `SessionContextService`、`SessionSummaryService`、`SessionTokenBudgetService` 和 `session_context_snapshots` 基础上，引入独立的模型预算注册表与压缩配置；将 planner 上下文固定为 `summary + recent completed turns + current turn transcript`；通过 default N、recent 原文比例上限与 15% 历史目标三组规则控制 recent working set 与 summary 滚动更新。

**Tech Stack:** Flutter 3.29.2（优先 `fvm flutter`）、Dart、flutter_test、当前 Session/turn/repository 架构。

---

## 文件地图

**新增**

- Create: `lib/models/session/context_compaction_config.dart`
- Create: `lib/models/session/model_budget_profile.dart`
- Create: `lib/services/model_budget_registry.dart`
- Create: `test/services/model_budget_registry_test.dart`

**修改**

- Modify: `lib/services/session_token_budget_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/session_summary_service.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/main.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `test/services/session_token_budget_service_test.dart`
- Modify: `test/services/session_context_service_test.dart`
- Modify: `test/services/session_summary_service_test.dart`

## Task 1: 建立模型预算与压缩配置

**Files:**
- Create: `lib/models/session/context_compaction_config.dart`
- Create: `lib/models/session/model_budget_profile.dart`
- Create: `lib/services/model_budget_registry.dart`
- Test: `test/services/model_budget_registry_test.dart`

- [ ] **Step 1: 先写模型预算注册表失败测试**

```dart
test('resolves exact model profile before family fallback', () {
  final registry = ModelBudgetRegistry(
    profiles: {
      'gpt-5': const ModelBudgetProfile(
        modelId: 'gpt-5',
        maxContextTokens: 200000,
        reservedOutputTokens: 16000,
        reasoningReserveTokens: 8000,
        safetyMarginTokens: 4000,
      ),
    },
    familyProfiles: {
      'gpt': const ModelBudgetProfile(
        modelId: 'gpt-family',
        maxContextTokens: 128000,
        reservedOutputTokens: 12000,
        reasoningReserveTokens: 8000,
        safetyMarginTokens: 4000,
      ),
    },
  );

  final profile = registry.resolve('gpt-5');

  expect(profile.maxContextTokens, 200000);
});
```

- [ ] **Step 2: 运行聚焦测试确认当前缺口**

Run: `fvm flutter test test/services/model_budget_registry_test.dart`

Expected: FAIL，提示缺少 `ModelBudgetRegistry`、`ModelBudgetProfile` 或配置模型。

- [ ] **Step 3: 新增 `ContextCompactionConfig`**

在 `lib/models/session/context_compaction_config.dart` 中定义配置对象，字段至少包含：

- `compressionTriggerRatio`
- `postCompressionHistoryRatio`
- `defaultRecentCompletedTurns`
- `recentTurnsMaxRatio`
- `minRecentCompletedTurns`

默认值写入模型本身，并为字段添加简短注释。

- [ ] **Step 4: 新增 `ModelBudgetProfile`**

在 `lib/models/session/model_budget_profile.dart` 中定义模型预算结构，字段至少包含：

- `modelId`
- `maxContextTokens`
- `reservedOutputTokens`
- `reasoningReserveTokens`
- `safetyMarginTokens`
- `compactionConfig`

- [ ] **Step 5: 实现 `ModelBudgetRegistry`**

在 `lib/services/model_budget_registry.dart` 中实现：

- 多层数据来源合并
- 精确匹配
- family 匹配
- fallback 默认值

第一版至少覆盖以下来源优先级：

- 当前 provider/model 的运行时显式覆盖
- 应用内置默认表
- fallback 默认值

如仓库中已有合适的本地 defaults/config 扩展入口，可以预留接口，但不要求在本任务中必须落地。

不要把 token 估算逻辑塞进 registry，只负责解析 profile。

- [ ] **Step 6: 运行测试并确认通过**

Run: `fvm flutter test test/services/model_budget_registry_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/models/session/context_compaction_config.dart lib/models/session/model_budget_profile.dart lib/services/model_budget_registry.dart test/services/model_budget_registry_test.dart
git commit -m "feat: add model budget registry"
```

## Task 2: 重构 SessionTokenBudgetService 为分项预算评估器

**Files:**
- Modify: `lib/services/session_token_budget_service.dart`
- Test: `test/services/session_token_budget_service_test.dart`

- [ ] **Step 1: 先写分项预算失败测试**

```dart
test('computes usable input budget with reasoning reserve and safety margin', () {
  final service = SessionTokenBudgetService(
    modelBudgetRegistry: ModelBudgetRegistry(
      profiles: {
        'test-model': const ModelBudgetProfile(
          modelId: 'test-model',
          maxContextTokens: 1000,
          reservedOutputTokens: 200,
          reasoningReserveTokens: 100,
          safetyMarginTokens: 50,
        ),
      },
    ),
  );

  final evaluation = service.evaluatePlannerBudget(
    modelName: 'test-model',
    fixedPrefixTokens: 200,
    summaryTokens: 100,
    recentTurnsTokens: 80,
    currentTurnTokens: 40,
  );

  expect(evaluation.usableInputBudget, 650);
  expect(evaluation.totalInputTokens, 420);
});
```

- [ ] **Step 2: 运行聚焦测试**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: FAIL，因为当前 service 还没有 `ModelBudgetRegistry` 和新的分项评估 API。

- [ ] **Step 3: 新增预算评估结果模型**

在 `SessionTokenBudgetService` 中定义或提取结果对象，至少包含：

- `usableInputBudget`
- `fixedPrefixTokens`
- `summaryTokens`
- `recentTurnsTokens`
- `currentTurnTokens`
- `historyPayloadTokens`
- `totalInputTokens`
- `totalUsageRatio`
- `shouldCompact`

- [ ] **Step 4: 接入 `ModelBudgetRegistry`**

替换当前通过模型名字符串 `contains()` 判断预算的逻辑，改为：

- 通过 registry 解析 `ModelBudgetProfile`
- 使用 profile 中的 `reasoningReserveTokens` 与 `compactionConfig`

- [ ] **Step 5: 增加 `evaluatePlannerBudget()`**

统一从以下分项计算预算：

- `fixedPrefixTokens`
- `summaryTokens`
- `recentTurnsTokens`
- `currentTurnTokens`

并用 `compressionTriggerRatio` 判断是否需要压缩。

- [ ] **Step 6: 保留现有粗估算器作为第一版 token 估算**

暂时保留字符级 `estimateTextTokens()`/`estimateMessagesTokens()`，但不要在该任务中继续扩散硬编码判断。

- [ ] **Step 7: 运行预算测试**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/services/session_token_budget_service.dart test/services/session_token_budget_service_test.dart
git commit -m "refactor: add planner budget evaluation"
```

## Task 3: 重构 SessionContextService 的上下文边界

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 先写边界不重叠失败测试**

```dart
test('does not duplicate current turn inside recent completed turns', () async {
  final messages = await service.buildPlannerMessages(
    groupId: 1,
    currentTurnId: 30,
    currentTurnTranscript: _eventsForTurn30(),
    config: _chatConfig(),
  );

  final combined = messages.map((m) => m.text).join('\n');

  expect(combined, contains('turn-29-user'));
  expect(combined, contains('turn-30-user'));
  expect(_countOccurrences(combined, 'turn-30-user'), 1);
});
```

- [ ] **Step 2: 再写 summary / recent / current 三层边界测试**

```dart
test('summary recent and current ranges remain mutually exclusive', () async {
  final result = await service.buildPlannerMessages(...);

  expect(result.debugSummaryCoveredUntilTurnId, 24);
  expect(result.debugRecentTurnIds, [25, 26, 27, 28, 29]);
  expect(result.debugCurrentTurnId, 30);
});
```

如果现有返回类型不支持调试字段，可以先通过内部 helper 单测覆盖边界，而不要为了测试把生产消息格式做脆弱编码。

- [ ] **Step 3: 运行聚焦测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: FAIL，当前 recent history 切分逻辑还没有 recent/current 的严格边界语义。

- [ ] **Step 4: 提取 completed turn segments**

在 `SessionContextService` 中新增 helper，把 `< currentTurnId` 的 turn 投影为 completed turn segments。

要求：

- 已被 snapshot 覆盖的 turn 不再进入 recent 候选
- 当前 turn 永不混入 completed turns

- [ ] **Step 5: 新增 recent completed turns 选择逻辑**

实现：

- 先取默认最近 `N` 个 completed turns
- 再按 `recentTurnsMaxRatio` 缩减
- 至少保留 `minRecentCompletedTurns`

- [ ] **Step 6: 将最终返回结构固定为**

- snapshot message（若存在）
- recent completed turns
- current turn transcript

不要让 `currentTurnTranscript` 与 `recent completed turns` 重叠。

- [ ] **Step 7: 运行测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/services/session_context_service.dart test/services/session_context_service_test.dart
git commit -m "refactor: split session context layers"
```

## Task 4: 引入 summary 滚动压缩与 15% 历史目标

**Files:**
- Modify: `lib/services/session_summary_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/session_summary_service_test.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 先写滚动 summary 失败测试**

```dart
test('rolls previous summary together with older completed turns', () async {
  final result = await service.summarizeHistory(
    previousSummary: '当前目标：完成最初需求',
    historicalMessages: [
      _message('用户后来新增约束：仅 Android'),
    ],
  );

  expect(result.summaryText, contains('完成最初需求'));
  expect(result.summaryText, contains('仅 Android'));
});
```

- [ ] **Step 2: 再写压缩后历史负载收紧测试**

```dart
test('shrinks history payload toward configured post-compression target', () async {
  final messages = await service.buildPlannerMessages(...);

  expect(result.debugHistoryPayloadRatio, lessThanOrEqualTo(0.15));
});
```

如果少数测试用例因固定前缀过大无法达到 0.15，应显式断言“总预算不超且 recent 已缩到最小兜底”。

- [ ] **Step 3: 运行聚焦测试**

Run: `fvm flutter test test/services/session_summary_service_test.dart test/services/session_context_service_test.dart`

Expected: FAIL，因为当前 summary service 只接收单次历史列表，没有 previous summary 合并语义。

- [ ] **Step 4: 扩展 SessionSummaryService**

新增或替换为：

- `summarizeHistory({ String? previousSummary, List<ChatMessage> historicalMessages })`

规则：

- 若有 `previousSummary`，先以 compact snapshot message 的形式作为输入首部
- 再追加本次要并入的 completed turn 消息

- [ ] **Step 5: 调整 summary 提示词结构**

在现有结构化栏目上新增：

- `已否决方案`

确保最早目标、后续限制和关键决策可以随着滚动 summary 持续存在。

- [ ] **Step 6: 在 SessionContextService 中实现压缩后续逻辑**

当达到阈值时：

- 将 recent 窗口之外的更早历史并入新 summary
- 更新 snapshot
- 重新评估历史负载
- 若 `summary + recent` 仍超过 `15%` 历史目标，则继续缩减 recent completed turns
- 至少保留 1 个 completed turn

- [ ] **Step 7: 运行测试**

Run: `fvm flutter test test/services/session_summary_service_test.dart test/services/session_context_service_test.dart`

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/services/session_summary_service.dart lib/services/session_context_service.dart test/services/session_summary_service_test.dart test/services/session_context_service_test.dart
git commit -m "feat: add rolling session compaction"
```

## Task 5: 接线、文档与回归验证

**Files:**
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/main.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 接入 provider 与 main 默认实例**

确保：

- `ModelBudgetRegistry`
- `SessionTokenBudgetService`
- `SessionContextService`

通过 provider 和 `main.dart` 正确注入。

- [ ] **Step 2: 更新 README**

补充说明新的 Session 上下文策略：

- 固定前缀
- history summary
- recent completed turns
- current turn
- 压缩触发与压缩目标

- [ ] **Step 3: 更新 AGENTS**

补充新的实现约束，至少写明：

- planner 上下文三层边界
- recent completed turns 的默认 `N + 比例上限 + 兜底` 规则
- 更早历史统一滚动进 summary

- [ ] **Step 4: 运行核心测试集**

Run: `fvm flutter test test/services/model_budget_registry_test.dart test/services/session_token_budget_service_test.dart test/services/session_context_service_test.dart test/services/session_summary_service_test.dart`

Expected: PASS。

- [ ] **Step 5: 运行分析**

Run: `fvm flutter analyze`

Expected: PASS，或仅有已有无关 warning，且本次改动不新增 analyze error。

- [ ] **Step 6: Commit**

```bash
git add lib/providers/chat_dependency_providers.dart lib/main.dart README.md AGENTS.md
git commit -m "docs: describe session context compaction strategy"
```

## 完成标准

满足以下条件才算本计划完成：

- planner 上下文稳定收敛为 `summary + recent completed turns + current turn transcript`
- `current turn` 不会重复出现在 recent completed turns 中
- recent completed turns 同时受默认数量与 `10%` 比例约束
- 所有退出 recent working set 的旧历史都会滚动进入 summary
- 历史负载目标默认收紧为 `15%`
- 当 15% 无法完全满足时，仍优先保证总预算不超窗
- README 与 AGENTS 已同步更新到当前策略
