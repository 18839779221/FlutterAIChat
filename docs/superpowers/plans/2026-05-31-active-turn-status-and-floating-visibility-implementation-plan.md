# 统一主状态条与悬浮可见性 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立事件驱动的统一主状态条，并在内联状态滚出视口时将同一状态悬浮到输入框上方。

**Architecture:** 保持 `TurnHarness -> AgentEventProcessor -> ChatTimelineProjection` 的正式事实链路不变，在 UI 投影层新增 `ActiveTurnStatusPresentation` 与 resolver，统一归纳当前唯一主状态。时间线内联状态条和输入框上方悬浮状态条都只消费这一份状态模型，再通过页面级可见性协调器决定宿主位置。

**Tech Stack:** Flutter 3.35.7, Dart, Riverpod, existing chat timeline projection stack, widget tests, provider/service tests

---

## 文件结构与职责

### 需要新增的文件

- `lib/models/chat/active_turn_status_presentation.dart`
  - 定义统一主状态模型、阶段枚举、来源枚举
- `lib/services/active_turn_status_resolver.dart`
  - 从 `ChatTimelineProjection` 与 `ChatSendState` 归纳唯一主状态
- `lib/widgets/chat_blocks/unified_turn_status_bar.dart`
  - 统一状态条 UI，支持内联与悬浮两类宿主
- `test/services/active_turn_status_resolver_test.dart`
  - 覆盖阶段优先级、tool 文案映射、兜底行为

### 需要重点修改的文件

- `lib/models/chat/chat_timeline_projection.dart`
  - 补充主状态锚点所需的稳定字段或关联信息
- `lib/providers/chat_dependency_providers.dart`
  - 接入新的状态 resolver provider，替换旧 resolver 暴露方式
- `lib/providers/chat_ui_providers.dart`
  - 暴露统一主状态 provider 与页面级可见性 provider
- `lib/widgets/chat_timeline/chat_timeline_item.dart`
  - 增加内联状态锚点与统一状态载荷字段
- `lib/widgets/chat_timeline/chat_timeline_row.dart`
  - 用统一状态条组件替换旧的 `LatestMessageRunningStatusTail`
- `lib/widgets/chat_message_list.dart`
  - 停止独立归纳 running tail，改为消费统一主状态并标记锚点 row
- `lib/pages/chat_page.dart`
  - 增加输入框上方悬浮状态条宿主与页面级可见性协调
- `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
  - 删除或降级为兼容壳，并内部转用统一状态条

### 需要重点验证的测试文件

- `test/services/active_turn_status_resolver_test.dart`
- `test/widgets/chat_blocks/chat_blocks_test.dart`
- `test/widgets/chat_message_list_test.dart`
- `test/pages/chat_page_test.dart`

### 实施前注意事项

- 当前工作区已有未提交改动；执行本计划时不要回退与本任务无关的变更
- 优先在状态投影层集中 richer status 规则，不要把新 if/else 散落到 `ChatPage` / `ChatMessageList` / `ChatInput`
- 每个任务都先写失败测试，再写最小实现，再跑测试，再提交

---

### Task 1: 建立统一主状态模型与事件驱动 resolver

**Files:**
- Create: `lib/models/chat/active_turn_status_presentation.dart`
- Create: `lib/services/active_turn_status_resolver.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Test: `test/services/active_turn_status_resolver_test.dart`

- [ ] **Step 1: 为 confirmation 优先级写失败测试**

```dart
test('confirmation status wins over tool and streaming phases', () {
  final resolver = ActiveTurnStatusResolver();
  final projection = ChatTimelineProjection(
    pendingToolConfirmation: ProjectedPendingToolConfirmation(
      message: confirmationMessage,
      invocation: confirmationInvocation,
    ),
    toolPresentationEvents: [runningToolEvent],
    runtimePreviewState: previewStateWithText,
  );

  final status = resolver.resolve(
    projection: projection,
    sendState: const ChatSendState(
      phase: ChatSendPhase.streamingResponse,
      isGenerating: true,
    ),
  );

  expect(status?.phase, ActiveTurnStatusPhase.awaitingConfirmation);
  expect(status?.text, '等待工具确认');
});
```

- [ ] **Step 2: 为 executingTool 的 tool 文案映射写失败测试**

```dart
test('running web_search maps to dedicated status copy', () {
  final status = resolver.resolve(
    projection: projectionWithRunningTool('web_search'),
    sendState: const ChatSendState(
      phase: ChatSendPhase.executingTool,
      isGenerating: false,
    ),
  );

  expect(status?.phase, ActiveTurnStatusPhase.executingTool);
  expect(status?.toolName, 'web_search');
  expect(status?.text, '正在联网搜索');
});
```

- [ ] **Step 3: 为 tool result 后回到 planning 写失败测试**

```dart
test('tool result without active streaming falls back to planning next step', () {
  final status = resolver.resolve(
    projection: projectionWithLatestToolResult(),
    sendState: const ChatSendState(
      phase: ChatSendPhase.preparing,
      isGenerating: false,
    ),
  );

  expect(status?.phase, ActiveTurnStatusPhase.planning);
  expect(status?.text, '正在规划下一步');
});
```

- [ ] **Step 4: 为事件不足时的 send phase 兜底写失败测试**

```dart
test('streaming phase falls back to generating reply when no richer signal exists', () {
  final status = resolver.resolve(
    projection: const ChatTimelineProjection(),
    sendState: const ChatSendState(
      phase: ChatSendPhase.streamingResponse,
      isGenerating: true,
    ),
  );

  expect(status?.phase, ActiveTurnStatusPhase.streamingResponse);
  expect(status?.text, '正在生成回复');
});
```

- [ ] **Step 5: 运行测试确认失败**

Run: `flutter test test/services/active_turn_status_resolver_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/active_turn_status_resolver_test.dart`

Expected: FAIL because the status model and resolver do not exist yet.

- [ ] **Step 6: 写最小实现**

实现：
- 新增 `ActiveTurnStatusPhase`、`ActiveTurnStatusSourceKind`、`ActiveTurnStatusPresentation`
- 新增 `ActiveTurnStatusResolver.resolve(...)`
- 将旧 `LatestMessageRunningStatusResolver` 中的 tool 文案映射迁移到新的 resolver
- 在 `chat_dependency_providers.dart` 中暴露新的 resolver provider

- [ ] **Step 7: 运行测试确认通过**

Run: `flutter test test/services/active_turn_status_resolver_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/active_turn_status_resolver_test.dart`

Expected: PASS

- [ ] **Step 8: 提交这一小步**

```bash
git add lib/models/chat/active_turn_status_presentation.dart lib/services/active_turn_status_resolver.dart lib/providers/chat_dependency_providers.dart test/services/active_turn_status_resolver_test.dart
git commit -m "feat: add active turn status resolver"
```

### Task 2: 让时间线消费统一主状态并替换旧 tail 组件

**Files:**
- Create: `lib/widgets/chat_blocks/unified_turn_status_bar.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_item.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 为统一状态条组件写失败测试**

```dart
testWidgets('unified turn status bar renders restrained running copy', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UnifiedTurnStatusBar(
          status: ActiveTurnStatusPresentation(
            phase: ActiveTurnStatusPhase.planning,
            text: '正在规划下一步',
            turnId: 'turn-1',
            allowFloating: true,
          ),
        ),
      ),
    ),
  );

  expect(find.text('正在规划下一步'), findsOneWidget);
});
```

- [ ] **Step 2: 为 message list 消费统一主状态写失败测试**

```dart
testWidgets('chat message list attaches unified status to the active anchor row', (tester) async {
  await _pumpMessageList(
    tester,
    messages: buildSimpleTurnMessages(),
    overrides: [
      activeTurnStatusPresentationProvider.overrideWith(
        (ref) => planningStatusForMessageId(4),
      ),
    ],
  );

  expect(find.byType(UnifiedTurnStatusBar), findsOneWidget);
  expect(find.text('正在规划下一步'), findsOneWidget);
});
```

- [ ] **Step 3: 为非锚点 row 不显示状态条写失败测试**

```dart
testWidgets('chat timeline row only renders status for the designated anchor item', (tester) async {
  // Build two assistant rows and assert only the anchor row gets the status bar.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart`

Expected: FAIL because the unified status bar and anchor-driven row wiring do not exist yet.

- [ ] **Step 5: 写最小实现**

实现：
- 抽取 `UnifiedTurnStatusBar`
- 在 `ChatTimelineItem` 上增加统一状态字段或 anchor 标记
- `ChatMessageList` 改为消费统一主状态 provider，不再调用旧 resolver
- `ChatTimelineRow` 改为渲染统一状态条
- 让旧 `LatestMessageRunningStatusTail` 删除或变成极薄兼容壳

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/widgets/chat_blocks/unified_turn_status_bar.dart lib/widgets/chat_timeline/chat_timeline_item.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/latest_message_running_status_tail.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart
git commit -m "feat: drive timeline status from active turn status"
```

### Task 3: 暴露主状态 provider 并建立页面级悬浮可见性协调

**Files:**
- Modify: `lib/models/chat/chat_timeline_projection.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/pages/chat_page.dart`
- Test: `test/pages/chat_page_test.dart`

- [ ] **Step 1: 为无可见锚点时显示悬浮状态条写失败测试**

```dart
testWidgets('chat page shows floating status above composer when anchor is not visible', (tester) async {
  await tester.pumpWidget(
    buildChatPage(
      overrides: [
        activeTurnStatusPresentationProvider.overrideWith(
          (ref) => planningStatusForMessageId(999),
        ),
        activeTurnStatusFloatingVisibilityProvider.overrideWith(
          (ref) => true,
        ),
      ],
    ),
  );

  expect(find.byKey(const ValueKey('floating-turn-status-bar')), findsOneWidget);
});
```

- [ ] **Step 2: 为锚点可见时隐藏悬浮状态条写失败测试**

```dart
testWidgets('chat page hides floating status when inline anchor is visible', (tester) async {
  await tester.pumpWidget(
    buildChatPage(
      overrides: [
        activeTurnStatusPresentationProvider.overrideWith(
          (ref) => planningStatusForMessageId(4),
        ),
        activeTurnStatusFloatingVisibilityProvider.overrideWith(
          (ref) => false,
        ),
      ],
    ),
  );

  expect(find.byKey(const ValueKey('floating-turn-status-bar')), findsNothing);
});
```

- [ ] **Step 3: 为页面无状态时两边都不显示写失败测试**

```dart
testWidgets('chat page omits floating status when no active turn status exists', (tester) async {
  // Assert no floating status bar is rendered when provider returns null.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/pages/chat_page_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/pages/chat_page_test.dart`

Expected: FAIL because floating status provider/wiring does not exist yet.

- [ ] **Step 5: 写最小实现**

实现：
- 在 `chat_ui_providers.dart` 中新增：
  - `activeTurnStatusPresentationProvider`
  - 页面级 floating visibility provider
- `ChatPage` 在 `ChatInput` 上方接入悬浮状态条宿主
- 为悬浮状态条添加稳定 key，便于测试与后续动效迭代

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/pages/chat_page_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/models/chat/chat_timeline_projection.dart lib/providers/chat_ui_providers.dart lib/pages/chat_page.dart test/pages/chat_page_test.dart
git commit -m "feat: add floating active turn status host"
```

### Task 4: 实现锚点可见性判定与宿主切换

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/pages/chat_page.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/pages/chat_page_test.dart`

- [ ] **Step 1: 为长消息滚出视口时切换到悬浮条写失败测试**

```dart
testWidgets('floating status appears when the inline status anchor scrolls out of view', (tester) async {
  await tester.pumpWidget(buildLongTimelineWithActiveStatus());

  await tester.drag(find.byType(ChatMessageList), const Offset(0, -800));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('floating-turn-status-bar')), findsOneWidget);
});
```

- [ ] **Step 2: 为锚点重新进入视口时撤销悬浮条写失败测试**

```dart
testWidgets('floating status disappears when the inline status anchor becomes visible again', (tester) async {
  // Scroll away, assert floating, scroll back, assert floating removed.
});
```

- [ ] **Step 3: 为边界抖动滞回写失败测试**

```dart
testWidgets('floating status does not flap when anchor is near the viewport edge', (tester) async {
  // Perform small scrolls around the threshold and assert stable visibility.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: FAIL because visibility coordination and threshold switching are not implemented yet.

- [ ] **Step 5: 写最小实现**

实现：
- 让时间线 row 暴露当前状态锚点的可见性所需标识
- 基于 scroll controller / viewport 计算当前锚点是否可见
- 新增轻量滞回策略，避免边界抖动
- 当锚点不可见时只显示悬浮条；可见时只显示内联条

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/providers/chat_ui_providers.dart lib/pages/chat_page.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart
git commit -m "feat: switch active turn status between inline and floating hosts"
```

### Task 5: 回归验证与文档收尾

**Files:**
- Modify: `docs/superpowers/plans/2026-05-31-active-turn-status-and-floating-visibility-implementation-plan.md`
- Verify: `docs/superpowers/specs/2026-05-31-active-turn-status-and-floating-visibility-design.md`
- Verify: affected source and test files from Tasks 1-4

- [ ] **Step 1: 跑服务与组件相关测试**

Run: `flutter test test/services/active_turn_status_resolver_test.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/active_turn_status_resolver_test.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 2: 跑与页面状态切换强相关的现有回归测试**

Run: `flutter test test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/tool_confirmation/tool_confirmation_bottom_bar_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

Expected: PASS

- [ ] **Step 3: 如有 analyzer 风险，运行针对性 analyze**

Run: `flutter analyze lib/models/chat/active_turn_status_presentation.dart lib/services/active_turn_status_resolver.dart lib/providers/chat_ui_providers.dart lib/widgets/chat_message_list.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/pages/chat_page.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter analyze lib/models/chat/active_turn_status_presentation.dart lib/services/active_turn_status_resolver.dart lib/providers/chat_ui_providers.dart lib/widgets/chat_message_list.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/pages/chat_page.dart`

Expected: No issues found

- [ ] **Step 4: 更新计划勾选状态并记录偏差**

更新：
- 勾选已完成步骤
- 若实际实现与 spec 有细微偏差，在计划或 PR 说明中明确记录

- [ ] **Step 5: 提交最终收尾**

```bash
git add docs/superpowers/plans/2026-05-31-active-turn-status-and-floating-visibility-implementation-plan.md
git commit -m "docs: finalize active turn status implementation plan"
```

## 备注

- 本计划默认先做统一主状态投影，再做宿主切换；不要倒序从悬浮条开始做
- 若实现过程中发现 `ChatTimelineProjection` 缺少稳定锚点字段，优先在 projection 层补齐，不要让 widget 退回消息重扫
- 若当前工作区 Flutter 版本不是 `3.35.7`，所有 `flutter` 命令应按仓库约定替换为 `fvm flutter`
