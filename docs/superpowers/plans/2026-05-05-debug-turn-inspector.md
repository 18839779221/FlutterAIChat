# Debug Turn Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在聊天页右上角提供一个仅 debug 包可见的 Turn Inspector，用结构化只读方式查看当前/最近 turn 的 Agent Loop 状态、时间线和上下文。

**Architecture:** 新增一个 debug 专用 projection service 统一聚合现有正式事实源与 runtime 事实源，不新增持久化。UI 只消费 projection，不自行拼业务状态。入口挂在聊天页右上角，默认查看当前活跃 turn，并支持最近几个 turn 切换。

**Tech Stack:** Flutter, Riverpod, existing chat turn/step/event repositories, runtime providers, trace recorder, widget tests

---

### Task 1: 新增 Debug Turn Inspector projection

**Files:**
- Create: `lib/models/debug/debug_turn_inspector_projection.dart`
- Create: `lib/models/debug/debug_turn_inspector_timeline_entry.dart`
- Create: `lib/models/debug/debug_turn_inspector_context_section.dart`
- Create: `lib/models/debug/debug_turn_option.dart`
- Create: `lib/services/debug/debug_turn_inspector_projection_service.dart`
- Test: `test/services/debug/debug_turn_inspector_projection_service_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('builds overview timeline and context sections from persisted and runtime facts', () async {
  final projection = service.build(...);
  expect(projection.turnOptions, isNotEmpty);
  expect(projection.activeTurnOverview, isNotNull);
  expect(projection.timelineEntries, isNotEmpty);
  expect(projection.contextSections, hasLength(7));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart`
Expected: FAIL，因为 projection service 还不存在。

- [ ] **Step 3: 最小实现**

实现一个只读聚合 service，从现有 repositories / runtime providers / trace snapshot 组装：
- `turnOptions`
- `activeTurnOverview`
- `timelineEntries`
- `contextSections`

要求：
- 不写数据库
- 不新增 debug 真相源
- 原始 payload 原样保留
- `Timeline` 的项必须带 `source` 和 `severity`

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/debug/debug_turn_inspector_projection.dart lib/models/debug/debug_turn_inspector_timeline_entry.dart lib/models/debug/debug_turn_inspector_context_section.dart lib/models/debug/debug_turn_option.dart lib/services/debug/debug_turn_inspector_projection_service.dart test/services/debug/debug_turn_inspector_projection_service_test.dart
git commit -m "feat: add debug turn inspector projection"
```

### Task 2: 接入右上角 debug 入口和面板容器

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Create: `lib/widgets/debug/debug_turn_inspector_sheet.dart`
- Create: `lib/widgets/debug/debug_turn_inspector_button.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Test: `test/widgets/debug/debug_turn_inspector_button_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('shows debug inspector button only in debug build', (tester) async {
  await pumpChatPage(...);
  expect(find.byType(DebugTurnInspectorButton), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/debug/debug_turn_inspector_button_test.dart`
Expected: FAIL，因为按钮和面板还不存在。

- [ ] **Step 3: 最小实现**

在聊天页右上角加一个仅 debug 可见的固定悬浮按钮，点击后打开 inspector sheet。
要求：
- 不占用输入框位置
- 不影响消息滚动
- 默认打开当前活跃 turn

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/debug/debug_turn_inspector_button_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/debug/debug_turn_inspector_sheet.dart lib/widgets/debug/debug_turn_inspector_button.dart lib/providers/chat_ui_providers.dart test/widgets/debug/debug_turn_inspector_button_test.dart
git commit -m "feat: add debug turn inspector entry"
```

### Task 3: 实现 Overview / Timeline / Context 三个 tab

**Files:**
- Create: `lib/widgets/debug/debug_turn_inspector_page.dart`
- Create: `lib/widgets/debug/debug_turn_inspector_tabs.dart`
- Create: `lib/widgets/debug/debug_turn_inspector_overview_tab.dart`
- Create: `lib/widgets/debug/debug_turn_inspector_timeline_tab.dart`
- Create: `lib/widgets/debug/debug_turn_inspector_context_tab.dart`
- Create: `lib/widgets/debug/debug_json_view.dart`
- Modify: `lib/widgets/debug/debug_turn_inspector_sheet.dart`
- Test: `test/widgets/debug/debug_turn_inspector_page_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('renders three tabs and raw json sections', (tester) async {
  await pumpInspector(...);
  expect(find.text('Overview'), findsOneWidget);
  expect(find.text('Timeline'), findsOneWidget);
  expect(find.text('Context'), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/debug/debug_turn_inspector_page_test.dart`
Expected: FAIL，因为页面和 tabs 还不存在。

- [ ] **Step 3: 最小实现**

实现三 tab：
- Overview 显示当前 turn 状态与诊断字段
- Timeline 按时间升序展示统一事件
- Context 展示 7 个 section，并允许展开原始 JSON

要求：
- 原始数据优先
- 允许读 raw payload
- 不做额外持久化

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/debug/debug_turn_inspector_page_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/debug/debug_turn_inspector_page.dart lib/widgets/debug/debug_turn_inspector_tabs.dart lib/widgets/debug/debug_turn_inspector_overview_tab.dart lib/widgets/debug/debug_turn_inspector_timeline_tab.dart lib/widgets/debug/debug_turn_inspector_context_tab.dart lib/widgets/debug/debug_json_view.dart lib/widgets/debug/debug_turn_inspector_sheet.dart test/widgets/debug/debug_turn_inspector_page_test.dart
git commit -m "feat: add debug turn inspector tabs"
```

### Task 4: 接入 turn 切换与最近 turn 列表

**Files:**
- Modify: `lib/services/debug/debug_turn_inspector_projection_service.dart`
- Modify: `lib/widgets/debug/debug_turn_inspector_sheet.dart`
- Test: `test/services/debug/debug_turn_inspector_projection_service_test.dart`
- Test: `test/widgets/debug/debug_turn_inspector_page_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('lists current and recent turns with the active turn selected', () async {
  final projection = service.build(...);
  expect(projection.turnOptions, hasLength(>1));
  expect(projection.selectedTurnId, equals(activeTurnId));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart`
Expected: FAIL，因为 turn 切换逻辑还没接。

- [ ] **Step 3: 最小实现**

实现最近几个 turn 的 selector，默认选择当前活跃 turn，支持手动切换。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/debug/debug_turn_inspector_projection_service.dart lib/widgets/debug/debug_turn_inspector_sheet.dart test/services/debug/debug_turn_inspector_projection_service_test.dart test/widgets/debug/debug_turn_inspector_page_test.dart
git commit -m "feat: support debug turn switching"
```

### Task 5: 真机验证与文档对齐

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`（如果最终实现改变了调试约束或运行方式）
- Test: `test/widgets/debug/debug_turn_inspector_page_test.dart`

- [ ] **Step 1: 跑关键测试**

Run:
`flutter test test/services/debug/debug_turn_inspector_projection_service_test.dart`
`flutter test test/widgets/debug/debug_turn_inspector_button_test.dart`
`flutter test test/widgets/debug/debug_turn_inspector_page_test.dart`

Expected: 全部 PASS

- [ ] **Step 2: 真机安装验证**

Run: `bash scripts/android_install_debug.sh`
Expected: debug APK 安装成功

- [ ] **Step 3: 真机复现**

使用最新的 `create_artifact` 真实 prompt 复现，确认：
- 能打开右上角 Debug Turn Inspector
- 能看到当前 turn 的 Overview / Timeline / Context
- 能看到 runtime stream / runtime draft / planner messages

- [ ] **Step 4: 文档更新**

如果最终实现和 spec 一致，补充 README 中的 debug 能力说明。

- [ ] **Step 5: 提交**

```bash
git add README.md AGENTS.md
git commit -m "docs: document debug turn inspector"
```

