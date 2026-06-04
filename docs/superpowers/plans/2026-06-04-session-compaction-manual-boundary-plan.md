# Session Compaction Manual Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化会话压缩摘要，支持 `/compact` 手动压缩，并在时间线显示轻量上下文压缩分界线。

**Architecture:** 复用现有 `SessionContextService`、`SessionSummaryService`、`session_context_snapshots` 架构，不新增记忆系统。压缩产物仍以整段文本写入 `summary_text`，后续模型上下文从该 summary user message 开始，covered 边界之前的历史只用于 UI 展示。UI 分界线是 timeline marker，不伪装成普通 user/assistant 消息，也不进入模型上下文。

**Tech Stack:** Flutter 3.35.7 via `fvm flutter`、Riverpod、sqflite/web storage、现有 chat event/message projection pipeline。

---

### Task 1: Summary Prompt 与 Snapshot Context 语义

**Files:**
- Modify: `lib/services/session_summary_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/session_summary_service_test.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 写失败测试，确认 summary prompt 要求结构化栏目但整体存储**

在 `test/services/session_summary_service_test.dart` 调整 prompt 断言：

```dart
expect(SessionSummaryService.summaryInstructionPrompt, contains('当前目标'));
expect(SessionSummaryService.summaryInstructionPrompt, contains('文件/工具/代码结论'));
expect(SessionSummaryService.summaryInstructionPrompt, contains('下一步'));
```

并保留现有 `summary.summaryText` 整体返回断言，不新增字段级解析断言。

- [ ] **Step 2: 运行失败测试**

Run: `fvm flutter test test/services/session_summary_service_test.dart`

Expected: FAIL，提示新栏目缺失。

- [ ] **Step 3: 更新 summary prompt**

仅修改 `SessionSummaryService.summaryInstructionPrompt`，要求模型输出固定栏目，但 `summaryText` 仍作为整段文本存储。

- [ ] **Step 4: 写失败测试，确认 snapshot 以 user context 进入模型上下文**

在 `test/services/session_context_service_test.dart` 增加断言：

```dart
final messages = await service.buildPlannerMessages(...);
final summaryMessage = messages.firstWhere((m) => m.text.contains('旧历史已经压缩'));
expect(summaryMessage.role, MessageRole.user);

final carriers = await service.buildPlannerCarriers(...);
expect(carriers.whereType<SyntheticCarrier>().first.text, contains('旧历史已经压缩'));
expect(carriers.whereType<SyntheticCarrier>().first.role, SyntheticCarrierRole.user);
```

如果 `SyntheticCarrierRole` API 名称不同，以实际 carrier 类型字段为准。

- [ ] **Step 5: 运行失败测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: FAIL，当前 snapshot carrier/message 是 system。

- [ ] **Step 6: 改 `SessionContextService` snapshot 投影**

将 planner message/carrier 中 snapshot summary 的角色改为 user，并用轻量包裹说明：

```text
<conversation-summary>
已压缩历史上下文：
...
</conversation-summary>
```

只改变模型可见投影，不改变 `session_context_snapshots.summary_text` 的原文存储。

- [ ] **Step 7: 跑目标测试**

Run:

```bash
fvm flutter test test/services/session_summary_service_test.dart
fvm flutter test test/services/session_context_service_test.dart
```

Expected: PASS。

### Task 2: 手动 `/compact` 与自动压缩共用服务入口

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/controllers/chat_controller.dart`
- Modify: `lib/controllers/chat_summary_controller.dart` 或新增窄 coordinator（按现有 provider 边界选择最小改动）
- Test: `test/services/session_context_service_test.dart`
- Test: `test/controllers/chat_controller_test.dart` 或 `test/providers/chat_controller_tool_flow_test.dart`

- [ ] **Step 1: 写失败测试，手动压缩当前 group completed turns**

在 `test/services/session_context_service_test.dart` 增加 `compactCompletedHistoryForGroup` 测试：

```dart
final result = await service.compactCompletedHistoryForGroup(
  groupId: groupId,
  keepRecentCompletedTurns: 1,
);
expect(result.didCompactHistory, isTrue);
expect(result.snapshot?.summaryText, contains('当前目标'));
expect(result.snapshot?.coveredUntilTurnId, olderTurnId);
```

- [ ] **Step 2: 运行失败测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: FAIL，方法不存在。

- [ ] **Step 3: 实现 service 方法**

复用 `_buildHistorySegments`、`_rollSummaryForward`。手动压缩规则：

- 只处理 completed turns。
- 默认保留最近 `defaultRecentCompletedTurns` 或调用方传入数量。
- 没有可压缩历史时返回 no-op result。
- 写入同一个 `SessionContextSnapshotRepository.upsertLatest`。

- [ ] **Step 4: 写失败测试，ChatController 触发手动压缩**

新增 controller 测试，mock/stub `SessionContextService` 或使用 repository fake，确认 `compactCurrentSession()` 读取当前 group 并调用服务。

- [ ] **Step 5: 实现 controller 入口**

在 `ChatController` 暴露：

```dart
Future<ManualSessionCompactionResult> compactCurrentSession()
```

设置发送状态为 preparing/status text，完成后恢复 idle。失败时抛错给 UI snackbar。

- [ ] **Step 6: 跑目标测试**

Run:

```bash
fvm flutter test test/services/session_context_service_test.dart
fvm flutter test test/controllers/chat_controller_test.dart
```

Expected: PASS。

### Task 3: Context Boundary Divider 持久化与渲染

**Files:**
- Modify: `lib/models/response/message_content_type.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/repositories/chat_event_repository.dart`
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_item.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Create: `lib/widgets/chat_timeline/context_boundary_divider.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/controllers/agent_event_processor_test.dart` 或现有 processor 覆盖文件

- [ ] **Step 1: 写失败测试，processor 把 compaction marker 写入 UI timeline**

新增 `ChatEventType.contextCompacted` 预期测试：

```dart
await processor.process(ChatEvent(
  eventType: ChatEventType.contextCompacted,
  content: '已压缩历史上下文',
  payloadJson: {'snapshotId': 1, 'coveredUntilTurnId': 3},
));
expect(insertedMessage.contentType, MessageContentType.contextBoundary);
expect(insertedMessage.text, '已压缩历史上下文');
```

- [ ] **Step 2: 运行失败测试**

Run: `fvm flutter test test/controllers/agent_event_processor_test.dart`

Expected: FAIL，event/content type 不存在。

- [ ] **Step 3: 增加 marker event/content type**

新增：

- `ChatEventType.contextCompacted`
- `MessageContentType.contextBoundary`
- `ChatEventRepository.appendContextCompacted(...)`
- `AgentEventProcessor` 将其写为 system/plain timeline marker message

在 `SessionContextService._eventsToCarriers` 中明确跳过该 event，保证不进模型上下文。

- [ ] **Step 4: 写失败测试，timeline 渲染 divider 而不是气泡**

在 `test/widgets/chat_message_list_test.dart` 构造一条 `contentBoundary` message，断言：

```dart
expect(find.byKey(ValueKey('context-boundary-divider')), findsOneWidget);
expect(find.text('已压缩历史上下文'), findsOneWidget);
expect(find.byType(UserAnchorBubble), findsNothing);
```

- [ ] **Step 5: 实现 divider item 和 widget**

新增 `ChatTimelineItemType.contextBoundary`，在 `_buildTimelineItems` 遇到 `MessageContentType.contextBoundary` 时单独生成 divider item。

`ContextBoundaryDivider` 视觉：

- 横向细线
- 中间轻量 label
- 文案固定：`已压缩历史上下文`
- 默认不展示副文案

- [ ] **Step 6: 跑目标测试**

Run:

```bash
fvm flutter test test/widgets/chat_message_list_test.dart
fvm flutter test test/controllers/agent_event_processor_test.dart
```

Expected: PASS。

### Task 4: `/compact` 输入命令与别名 `/compat`

**Files:**
- Modify: `lib/widgets/chat_input.dart`
- Test: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: 写失败测试，slash suggestion 显示内置 compact 命令**

输入 `/com`，断言 suggestion 面板包含 `/compact` 和说明/或文案 `已压缩历史上下文`。

- [ ] **Step 2: 写失败测试，提交 `/compact` 不发送普通消息**

使用 spy `ChatController`，输入 `/compact` 后点击发送，断言：

- `compactCurrentSession()` 被调用一次
- `sendMessageRequest` 未被调用
- 输入框清空

同样覆盖 `/compat` 别名。

- [ ] **Step 3: 运行失败测试**

Run: `fvm flutter test test/widgets/chat_input_test.dart`

Expected: FAIL，命令不存在。

- [ ] **Step 4: 实现输入命令识别**

在 `ChatInput.submitCurrentInput` 前置处理：

- trim 后等于 `/compact` 或 `/compat`
- attachments 必须为空，否则提示错误
- 调用 `chatController.compactCurrentSession()`
- 成功后清空输入
- 失败显示 snackbar

slash suggestion 复用现有 skill suggestion 面板样式，可先混合内置命令和 skill 结果。

- [ ] **Step 5: 跑目标测试**

Run: `fvm flutter test test/widgets/chat_input_test.dart`

Expected: PASS。

### Task 5: 自动压缩插入同一 Divider

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart` 或调用 `SessionContextService` 的上下文构建处
- Test: `test/services/session_context_service_test.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`

- [ ] **Step 1: 写失败测试，自动压缩成功后产生 contextCompacted event/message**

在现有高压预算自动压缩测试附近，断言压缩成功后可观察到 marker event 或 message。

- [ ] **Step 2: 运行失败测试**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: FAIL，自动压缩只写 snapshot 不写 marker。

- [ ] **Step 3: 实现 marker 写入**

自动与手动共用 helper：

```dart
appendContextCompacted(
  content: '已压缩历史上下文',
  payloadJson: {
    'snapshotId': snapshot.id,
    'coveredUntilTurnId': snapshot.coveredUntilTurnId,
    'trigger': 'auto' | 'manual',
  },
)
```

如果当前压缩发生在 running turn 内，用当前 turn id 写 marker event；手动压缩可创建一个 system/internal completed turn 或复用最近可安全承载 marker 的机制。优先选择不污染模型上下文且 UI 可排序稳定的最小方案。

- [ ] **Step 4: 跑相关测试**

Run:

```bash
fvm flutter test test/services/session_context_service_test.dart
fvm flutter test test/controllers/chat_send_coordinator_test.dart
```

Expected: PASS。

### Task 6: 文档与收口验证

**Files:**
- Modify: `docs/architecture/session-context-management.md`
- Maybe Modify: `README.md`

- [ ] **Step 1: 更新架构文档**

补充：

- summary prompt 是结构化输出要求，但 summary 原文整体存储
- snapshot summary 作为 user context 起点
- context boundary divider 是 UI marker，不进入模型上下文
- `/compact` 和自动 compact 共享行为

- [ ] **Step 2: 运行 targeted analyze**

Run:

```bash
fvm flutter analyze lib/services/session_summary_service.dart lib/services/session_context_service.dart lib/widgets/chat_input.dart lib/widgets/chat_message_list.dart lib/widgets/chat_timeline
```

Expected: PASS 或仅剩与本次无关的既有 warning。

- [ ] **Step 3: 运行最终目标测试**

Run:

```bash
fvm flutter test test/services/session_summary_service_test.dart
fvm flutter test test/services/session_context_service_test.dart
fvm flutter test test/widgets/chat_input_test.dart
fvm flutter test test/widgets/chat_message_list_test.dart
```

Expected: PASS。
