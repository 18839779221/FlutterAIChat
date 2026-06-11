# Context Usage Panel User-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 App 内 `context usage` 面板从预算/诊断字段列表改成用户视角的上下文占用地图，新增 grid 主图、分类占用条、工具/网页/文件结果 Top 5，并把技术细节下沉为折叠区。

**Architecture:** 继续以 `SessionContextInspectorService` 为唯一面板数据入口，在现有 `ContextWindowSnapshot + segments` 的基础上补齐用户视角分类和 Top 5 数据模型。UI 层保持当前 bottom sheet 入口不变，只重写详情面板结构与可视化方式；composer 小圆环仍沿用现有触发口径，不在本轮改动。

**Tech Stack:** Flutter 3.35.7, Dart, Riverpod wiring already in place, existing `ContextWindowSnapshot` / `SessionContextInspectorService`, Flutter widget tests

---

## 文件结构与职责

### 需要新增的文件

- `lib/models/session/context_usage_category.dart`
  - 用户视角分类模型
- `lib/models/session/context_usage_top_item.dart`
  - Top 5 操作项模型
- `test/models/session/context_usage_models_test.dart`
  - 分类与 Top item 的最小数据契约测试

### 需要重点修改的文件

- `lib/models/session/context_window_snapshot.dart`
  - 扩展 snapshot，加入主面板所需的用户视角字段
- `lib/services/session_context_inspector_service.dart`
  - 从原始 events / projected context 中计算分类占用与 Top 5
- `lib/widgets/context_window/context_window_bottom_sheet.dart`
  - 重写为 grid + 分类条 + Top 5 + 折叠技术细节
- `test/services/session_context_inspector_service_test.dart`
  - 补分类与 Top 5 的服务层测试
- `test/widgets/context_window/context_window_bottom_sheet_test.dart`
  - 锁定新的主视觉与主结构

### 可选同步文件

- `README.md`
  - 如果 repo 顶层文档提到旧版 context usage 面板表达方式，则补一条简短更新

## 实施策略

- 先补数据模型和服务层，确保 snapshot 能表达用户视角结构
- 再补 widget 测试，锁定 grid / 分类 / Top 5 / 技术细节折叠区
- 最后重写 bottom sheet UI
- 保持入口和 composer indicator 不变，避免本轮同时触碰两套交互

---

### Task 1: 扩展 snapshot 数据模型

**Files:**
- Create: `lib/models/session/context_usage_category.dart`
- Create: `lib/models/session/context_usage_top_item.dart`
- Modify: `lib/models/session/context_window_snapshot.dart`
- Test: `test/models/session/context_usage_models_test.dart`

- [ ] **Step 1: 先写失败测试，锁定分类与 Top item 最小契约**

```dart
test('context usage category exposes label tokens and total share', () {
  const category = ContextUsageCategory(
    type: ContextUsageCategoryType.recentConversation,
    label: '最近对话',
    estimatedTokens: 18000,
    shareOfTotalWindow: 0.14,
  );

  expect(category.label, '最近对话');
  expect(category.estimatedTokens, 18000);
});

test('context usage top item keeps tool label and total share', () {
  const item = ContextUsageTopItem(
    toolName: 'fetch_webpage',
    objectLabel: 'openai.com/pricing',
    estimatedTokens: 12000,
    shareOfTotalWindow: 0.09,
  );

  expect(item.toolName, 'fetch_webpage');
  expect(item.objectLabel, contains('openai.com'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/session/context_usage_models_test.dart`

Expected: FAIL because the new models do not exist yet.

- [ ] **Step 3: 写最小模型实现并扩展 snapshot**

实现：

- 定义 `ContextUsageCategoryType`
- 定义 `ContextUsageCategory`
- 定义 `ContextUsageTopItem`
- 在 `ContextWindowSnapshot` 中补：
  - `usedWindowTokens`
  - `usedWindowRatio`
  - `categories`
  - `topItems`

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/models/session/context_usage_models_test.dart`

Expected: PASS

### Task 2: 为 inspector 增加用户视角分类与 Top 5

**Files:**
- Modify: `lib/services/session_context_inspector_service.dart`
- Modify: `test/services/session_context_inspector_service_test.dart`

- [ ] **Step 1: 写失败测试，锁定 snapshot 会输出用户分类**

```dart
test('snapshot groups usage into user-facing categories', () async {
  final snapshot = await inspector.buildLatestWindowSnapshot(...);

  expect(
    snapshot.categories.map((item) => item.label),
    containsAll(<String>['最近对话', '工具 / 网页 / 文件结果', '历史摘要', '系统设定']),
  );
});
```

- [ ] **Step 2: 写失败测试，锁定 Top 5 只包含工具/网页/文件结果**

```dart
test('snapshot exposes top tool-heavy items sorted by token cost', () async {
  final snapshot = await inspector.buildLatestWindowSnapshot(...);

  expect(snapshot.topItems, isNotEmpty);
  expect(snapshot.topItems.first.estimatedTokens, greaterThan(0));
  expect(snapshot.topItems.first.displayLabel, contains('·'));
});
```

- [ ] **Step 3: 运行服务层测试确认失败**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart`

Expected: FAIL because `ContextWindowSnapshot` does not yet expose categories/top items and the inspector does not compute them.

- [ ] **Step 4: 写最小服务实现**

实现：

- 保留原始 `segments` 输出，避免技术细节区丢失
- 新增事件级 usage item 提取：
  - system prompt
  - runtime user context
  - history summary
  - recent/current 普通对话
  - tool result / tool error
  - reserves / free headroom
- 按用户分类聚合 tokens
- 计算 `usedWindowTokens` 与 `usedWindowRatio`
- 仅从工具结果中提取 Top 5
- 对象名简单取已有字段，不新增解释生成

- [ ] **Step 5: 运行服务层测试确认通过**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart`

Expected: PASS

### Task 3: 重写 bottom sheet 主结构

**Files:**
- Modify: `lib/widgets/context_window/context_window_bottom_sheet.dart`
- Modify: `test/widgets/context_window/context_window_bottom_sheet_test.dart`

- [ ] **Step 1: 写失败测试，锁定新面板结构**

```dart
testWidgets('bottom sheet shows usage grid categories top items and collapsed technical details', (tester) async {
  await tester.pumpWidget(...);

  expect(find.text('Top 5'), findsOneWidget);
  expect(find.text('最近对话'), findsOneWidget);
  expect(find.byKey(const ValueKey('context-usage-grid')), findsOneWidget);
});
```

- [ ] **Step 2: 运行 widget 测试确认失败**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: FAIL because the current sheet still renders the old summary/section layout.

- [ ] **Step 3: 写最小 UI 实现**

实现：

- 顶部：`waffle/grid + 百分比主数字 + tokens 副信息`
- 中段：分类短条列表
- 下段：Top 5 + mini bars
- 底部：默认折叠的技术细节区
- 继续复用当前 bottom sheet 入口和主题 token

- [ ] **Step 4: 运行 widget 测试确认通过**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: PASS

### Task 4: 收口回归与文档同步

**Files:**
- Modify: `test/widgets/context_window/context_window_bottom_sheet_test.dart`
- Modify: `test/services/session_context_inspector_service_test.dart`
- Optional Modify: `README.md`

- [ ] **Step 1: 串行跑相关测试**

Run:

```bash
fvm flutter test test/models/session/context_usage_models_test.dart
fvm flutter test test/services/session_context_inspector_service_test.dart
fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart
fvm flutter test test/widgets/context_window/context_window_usage_indicator_test.dart
```

Expected: PASS

- [ ] **Step 2: 跑定向 analyze**

Run:

```bash
fvm flutter analyze \
  lib/models/session/context_usage_category.dart \
  lib/models/session/context_usage_top_item.dart \
  lib/models/session/context_window_snapshot.dart \
  lib/services/session_context_inspector_service.dart \
  lib/widgets/context_window/context_window_bottom_sheet.dart \
  test/models/session/context_usage_models_test.dart \
  test/services/session_context_inspector_service_test.dart \
  test/widgets/context_window/context_window_bottom_sheet_test.dart
```

Expected: PASS or only unrelated pre-existing noise outside touched files.

- [ ] **Step 3: 如有必要补 repo 文档**

如果 `README.md` 中对 context usage 面板描述仍明显停留在旧结构，则补一条简短更新；否则不动。

