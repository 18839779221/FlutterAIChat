# ChatSendCoordinator 事件分发器实现计划

## 目标

基于 `docs/superpowers/specs/2026-04-24-chat-send-coordinator-event-dispatcher-design.md`，抽出 `AgentEventProcessor`，让 `_sendMessageWithAgentLoop` / `submitQuestionAnswers` / `_resumeAgentLoopConfirmation` 三个方法共用同一套事件消费逻辑，差异通过 hook 注入。

## 代码结构与职责

### 需要修改的文件

- 修改：`lib/controllers/chat_send_coordinator.dart`
  - `_sendMessageWithAgentLoop` / `submitQuestionAnswers` / `_resumeAgentLoopConfirmation` 内部 switch-case 替换为 `processor.handle(event)`
  - 保留 `_appendVisibleSendFailureMessage` / `_syncAssistantFailureState` / `_formatSendFailureText` / `_resolveTraceTurnId` / `_resolveLatestMessageById` / `_loadGroups`

### 需要新增的文件

- 新增：`lib/controllers/agent_event_processor.dart`
  - `class AgentEventProcessor`
  - `class AgentEventHooks`
  - 内部从 coordinator 搬入 `_appendToolResultMessage` / `_createAssistantStreamBuffer` / `_finalizeAssistantText` / `_buildToolFailurePayload`（如这些仅被 processor 使用则完全迁移；若 coordinator 其他位置也用则拆为工具函数）

### 需要修改/新增的测试文件

- 修改：`test/providers/chat_controller_tool_flow_test.dart`
  - 如已覆盖 sendMessage 路径则补 submitQuestionAnswers / resumeConfirmation 路径
- 新增：`test/controllers/agent_event_processor_test.dart`
  - 直接对 processor 做单元测试（不涉及 harness）

## 实施步骤

### 任务 1：补齐三路径的集成测试（行为锁定）

**文件：**

- 修改：`test/providers/chat_controller_tool_flow_test.dart`
- 参考：`lib/controllers/chat_send_coordinator.dart`

- [ ] **Step 1: 盘点现有覆盖**

列出测试里已经模拟了哪些 `ChatEvent` 序列，哪些路径 / 哪些事件类型未覆盖。重点确认：

- `assistantToolConfirmation` → `confirmToolInvocation` → `_resumeAgentLoopConfirmation` 路径是否有测试
- `assistantQuestionPrompt` → `submitQuestionAnswers` 路径是否有测试
- `toolError` 路径是否有测试
- cancel 路径是否有测试

- [ ] **Step 2: 补齐 sendMessage 路径测试**

通过 fake `TurnHarness` 发事件序列，断言：

- DB insert 调用次数、顺序、payload
- `messagesProvider` 状态终态
- `chatSendStateProvider.phase` 变化序列
- trace 记录项

- [ ] **Step 3: 补齐 submitQuestionAnswers 路径测试**

覆盖 `userInteractionResult` 的替换语义（ask-prompt 被替换而不是新增）。

- [ ] **Step 4: 补齐 _resumeAgentLoopConfirmation 路径测试**

覆盖首个 `toolExecutionStarted` 替换 confirmation 消息的语义、`hasPendingConfirmation` 为 true 时的 phase 收尾。

- [ ] **Step 5: 运行测试，确认当前主干全绿**

```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

预期：PASS（基线）

### 任务 2：抽出 AgentEventProcessor

**文件：**

- 新增：`lib/controllers/agent_event_processor.dart`
- 新增：`test/controllers/agent_event_processor_test.dart`

- [ ] **Step 6: 定义 AgentEventHooks 与 AgentEventProcessor 骨架**

按 design 中的字段签名写出接口，所有 handle 分支先 throw UnimplementedError。

- [ ] **Step 7: 实现默认事件处理（不涉及 hook 分支）**

从 `_sendMessageWithAgentLoop` 的 switch-case 复制实现到 processor 内：

- `assistantPlannerMessage` / `assistantToolCall` / `assistantToolConfirmation` / `assistantQuestionPrompt` / `toolExecutionStarted` / `toolResult` / `toolError` / `assistantTextDelta` / `finalAnswer` / `userInteractionResult`

内部持有 `_assistantMessageId` / `_assistantMessage` / `_assistantStreamBuffer` / `_hasPendingConfirmation`。

- [ ] **Step 8: 接入 hooks**

- `onFinalAnswer`：默认动作之后调用
- `onAssistantToolConfirmation`：默认动作之后调用
- `onUserInteractionResult`：动作之前调用，返回 true 跳过默认
- `transformFirstToolExecution`：动作之前调用，返回 true 跳过默认

- [ ] **Step 9: 实现 `dispose`**

取消 stream buffer、标记 processor 为 disposed。

- [ ] **Step 10: 写 processor 单测**

对每个事件类型写：

- 默认行为断言
- hook 行为断言（hook 返回 true 跳过默认 / hook 返回 false 继续默认）

```bash
fvm flutter test test/controllers/agent_event_processor_test.dart
```

预期：PASS

### 任务 3：迁移 sendMessage 路径

**文件：**

- 修改：`lib/controllers/chat_send_coordinator.dart`

- [ ] **Step 11: 替换 `_sendMessageWithAgentLoop` 内部 switch 为 processor.handle**

```dart
final processor = AgentEventProcessor(
  ref: _ref,
  groupId: currentGroupId,
  traceTurnId: turnId,
  agentTurnId: turnRecordId,
  traceRecorder: traceRecorder,
  hooks: AgentEventHooks(
    onFinalAnswer: (event) {
      traceRecorder.record(/* sendDone */);
      scheduleAutoSummary();
    },
    onAssistantToolConfirmation: (event) {
      traceRecorder.record(/* sendDone awaitingConfirmation */);
    },
  ),
);

final subscription = harness.runTurn(...).asyncMap((event) async {
  await processor.handle(event);
}).listen(
  (_) {},
  onError: (error, stackTrace) {
    // 复用原 onError 逻辑，但 buffer 清理交给 processor.dispose
    unawaited(processor.dispose());
    _syncAssistantFailureState(
      groupId: currentGroupId,
      assistantMessageId: processor.assistantMessageId,
      rawError: error,
    );
    // ...
  },
  onDone: () { /* ... */ },
  cancelOnError: true,
);
```

- [ ] **Step 12: 运行测试**

```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

预期：PASS

### 任务 4：迁移 submitQuestionAnswers 路径

**文件：**

- 修改：`lib/controllers/chat_send_coordinator.dart`

- [ ] **Step 13: 替换 `submitQuestionAnswers` 内部 switch**

通过 `onUserInteractionResult` hook 注入替换消息逻辑：

```dart
onUserInteractionResult: (event) async {
  final resultMessage = message.copyWith(
    text: event.content ?? message.text,
    contentType: MessageContentType.askUserQuestionResult,
    payloadJson: { ... submittedAnswers, status, traceTurnIdPayloadKey },
  );
  _ref.read(messagesProvider.notifier).replaceMessage(resultMessage);
  await dbHelper.updateStructuredMessage(message.id!, ...);
  return true;
},
```

- [ ] **Step 14: 统一 streamSubscriptionProvider 收尾**

`finally` 块从原 submitQuestionAnswers 保留，改为 await processor.dispose()。

- [ ] **Step 15: 运行测试**

```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

预期：PASS

### 任务 5：迁移 _resumeAgentLoopConfirmation 路径

**文件：**

- 修改：`lib/controllers/chat_send_coordinator.dart`

- [ ] **Step 16: 替换 switch**

```dart
var firstToolExec = true;
final processor = AgentEventProcessor(
  ref: _ref,
  groupId: currentGroupId,
  traceTurnId: traceTurnId,
  agentTurnId: turnId,
  hooks: AgentEventHooks(
    transformFirstToolExecution: (event) async {
      if (!firstToolExec) return false;
      firstToolExec = false;
      final runningPayload = { ...?event.payloadJson, 'agentTurnId': turnId, traceTurnIdPayloadKey: traceTurnId };
      final runningMessage = sourceMessage.copyWith(...);
      _ref.read(messagesProvider.notifier).replaceMessage(runningMessage);
      await dbHelper.updateStructuredMessage(sourceMessageId, ...);
      return true;
    },
  ),
);

await for (final event in harness.resumeAfterConfirmation(...)) {
  await processor.handle(event);
}

await processor.dispose();
_ref.read(chatSendStateProvider.notifier).setPhase(
  processor.hasPendingConfirmation
    ? ChatSendPhase.awaitingConfirmation
    : ChatSendPhase.idle,
);
```

- [ ] **Step 17: 补齐 streamSubscriptionProvider 注册**

对齐三路径：`_resumeAgentLoopConfirmation` 也注册订阅，以便外部 cancel 生效（之前缺）。

- [ ] **Step 18: 运行测试**

```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart
```

预期：PASS

### 任务 6：清理死代码

**文件：**

- 修改：`lib/controllers/chat_send_coordinator.dart`

- [ ] **Step 19: 删除被替换的 switch 块和局部变量**

确认三个方法不再各自持有 `assistantMessageId` / `assistantMessage` / `assistantStreamBuffer`。

如 `_appendToolResultMessage` / `_createAssistantStreamBuffer` / `_finalizeAssistantText` / `_buildToolFailurePayload` 已全部迁移到 processor，则从 coordinator 删除。

- [ ] **Step 20: 运行全量测试 + analyze**

```bash
fvm flutter test
fvm flutter analyze
```

预期：

- 全部 PASS
- `chat_send_coordinator.dart` 降到 ~500 行（通过 `wc -l` 验证）
- `agent_event_processor.dart` ~400 行

### 任务 7：真机冒烟

**文件：** 无代码改动

- [ ] **Step 21: 覆盖所有真机路径**

- 普通发送 → 完成
- 发送 → 工具 awaitingConfirm → 确认 → 继续
- 发送 → 工具 awaitingConfirm → 取消
- 发送 → ask user question → 回答 → 继续
- 发送 → 中途 cancel（点击停止）
- 发送 → 工具执行失败
- 多轮 tool loop（连续多个 tool call）

预期：

- 消息时间线视觉无回归
- trace 日志完整（对比重构前 log）
- phase 状态灯（发送按钮 / 停止按钮）切换无回归

## 受影响回归面

- 任何依赖 `ChatEvent` 处理顺序的上层逻辑：由任务 1 的集成测试覆盖
- `streamSubscriptionProvider` 对接的停止按钮：任务 5 后需要额外验证 `_resumeAgentLoopConfirmation` 路径也能被停止
- reasoning-visibility plan：若此时并行推进，`assistantReasoningDelta` 的处理应在 processor 内落地，不在 coordinator
