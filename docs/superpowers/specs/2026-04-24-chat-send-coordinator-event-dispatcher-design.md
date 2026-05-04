# ChatSendCoordinator 事件分发器设计

## 背景

`lib/controllers/chat_send_coordinator.dart` 当前 1273 行，核心是三个方法对 `TurnHarness` 发出的 `Stream<ChatEvent>` 做 switch-case 消费：

- `_sendMessageWithAgentLoop`（新发送路径，L175–478）
- `submitQuestionAnswers`（ask-user-question 回复后恢复路径，L649–922）
- `_resumeAgentLoopConfirmation`（工具确认后恢复路径，L924–1164）

三个方法对大多数 `ChatEventType`（`assistantPlannerMessage` / `assistantToolCall` / `assistantToolConfirmation` / `assistantQuestionPrompt` / `toolExecutionStarted` / `toolResult` / `toolError` / `assistantTextDelta` / `finalAnswer` / `userInteractionResult`）的处理逻辑重复超过 200 行，重复块包含：

- 构造 `ChatMessage`、注入 `payloadJson`
- `dbHelper.insertMessage` 写库
- `_ref.read(messagesProvider.notifier).addMessage`
- `AssistantStreamOutputBuffer` 的懒创建 + `onDelta` + finalize
- `chatSendStateProvider` 的 phase 推进

差异点局部且有限：

| 差异点 | sendMessage | submitQuestionAnswers | _resumeAgentLoopConfirmation |
|--------|-------------|-----------------------|------------------------------|
| `agentTurnId` 是否注入 payload | 是（末尾流程） | 是 | 是 |
| `traceTurnIdPayloadKey` 是否注入 | 部分事件 | 是 | 是 |
| `userInteractionResult` 默认行为 | `addMessage` 新建 | **替换** ask-prompt 消息 | `addMessage` 新建 |
| 首个 `toolExecutionStarted` | `addMessage` 新建 | `addMessage` 新建 | **替换** confirmation 消息 |
| `finalAnswer` 后置动作 | trace + `scheduleAutoSummary` | 无 | 无 |
| `assistantToolConfirmation` trace 记录 | 有 | 无 | 无 |
| 结束后的 phase 收尾 | onDone 无额外处理 | `finally` 兜底 phase idle | 根据 `hasPendingConfirmation` 决定 |

这种重复已经产生了实际不一致：

- `sendMessage` 路径通过 `streamSubscriptionProvider` 注册订阅并支持外部 `cancel`，另外两个路径部分路径有 / 部分路径没有
- Trace 记录点分散且不对称（`sendMessage` 多、其他少）
- `phase` 收尾在三处用不同代码形态表达，改一处容易漏两处

anthropic-compatible continuation、reasoning visibility 两条并行线都需要在事件消费层做扩展；继续维持三份 switch 的成本会线性增长。

## 目标

1. 抽出 `AgentEventProcessor`：对单个 `ChatEvent` 的默认处理（插消息 / 写库 / 推 phase / 管理 stream buffer）收敛到一处。
2. 三个方法缩减为：
   - 构造 processor（注入 groupId / traceTurnId / 可选 agentTurnId / 可选 hook）
   - 订阅 harness 流并把事件交给 processor
   - 处理 `onError` / `onDone` / `finally`（订阅取消、buffer dispose、phase 兜底）
3. 差异行为通过显式 **hook 参数**注入，不通过子类化。
4. 重构保持对外可观测行为不变。

## 非目标

- 不修改 `TurnHarness` / `ChatEvent` / `ChatEventType` 的结构或语义
- 不修改 `ChatSendPhase` 状态机
- 不修改 `AssistantStreamOutputBuffer` 接口
- 不调整 trace 记录的语义或字段（只搬动位置）
- 不合并三个外层方法（`sendMessage` / `submitQuestionAnswers` / `confirmToolInvocation` 对外签名保持不变）
- 不引入新的 provider

## 现状分析

### 现有能力

- `ChatEvent` 已经是标准化、可枚举的事件类型
- `AssistantStreamOutputBuffer` 已经处理了 UI / 持久化双节流
- `messagesProvider.notifier.addMessage / replaceMessage / updateMessage / updateMessageStatus` 提供了统一的消息状态更新入口
- `chatSendStateProvider` 集中了 phase 状态
- `ChatTraceRecorder` 提供了统一 trace 记录

### 现有缺口

1. 没有一个"事件消费"抽象，每个路径重新写一遍 switch-case
2. `assistantMessageId` / `assistantMessage` / `assistantStreamBuffer` 三个局部状态在三个方法里各自维护，没法跨路径复用
3. 辅助函数 `_appendToolResultMessage` / `_createAssistantStreamBuffer` / `_finalizeAssistantText` / `_buildToolFailurePayload` 已经抽了出来，但更大的 switch-case 主体还没抽
4. `streamSubscriptionProvider` 的注册 / 注销时机不一致（`sendMessage` 注册、`submitQuestionAnswers` 注册且在 finally 清理、`_resumeAgentLoopConfirmation` 完全不注册）

## 设计方案

### AgentEventProcessor 抽象

```dart
class AgentEventProcessor {
  AgentEventProcessor({
    required Ref ref,
    required int groupId,
    required String traceTurnId,
    int? agentTurnId,
    ChatTraceRecorder? traceRecorder,
    AgentEventHooks hooks = const AgentEventHooks(),
  });

  Future<void> handle(ChatEvent event);

  Future<void> dispose();

  // 只读暴露给外层做收尾判断
  bool get hasPendingConfirmation;
  int? get assistantMessageId;
}
```

Hook 形态（命名字段而不是位置参数，便于扩展）：

```dart
class AgentEventHooks {
  const AgentEventHooks({
    this.onFinalAnswer,
    this.onAssistantToolConfirmation,
    this.onUserInteractionResult,
    this.transformFirstToolExecution,
  });

  final FutureOr<void> Function(ChatEvent event)? onFinalAnswer;
  final FutureOr<void> Function(ChatEvent event)? onAssistantToolConfirmation;
  final FutureOr<bool> Function(ChatEvent event)? onUserInteractionResult;
  final FutureOr<bool> Function(ChatEvent event)? transformFirstToolExecution;
}
```

Hook 约定：

- 返回 `bool` 的 hook，`true` 表示"hook 已完全处理"，processor 跳过默认行为；`false` 表示 hook 处理完附加逻辑，继续执行默认行为
- `onFinalAnswer` / `onAssistantToolConfirmation` 返回 `void`，不影响默认行为（默认仍执行）
- 所有 hook 都是 optional

### 内部默认行为

processor 内部按 `ChatEvent.eventType` 分发：

- `userMessage` / `assistantTextFinal` / `turnStatus` / `error`：no-op
- `assistantReasoningDelta`：
  - `tool_use` scope：持久化为独立 assistant analysis 消息，保持“thinking -> tool -> result”的时间线顺序
  - final-answer / response scope：写入当前 response draft 或最终答复消息
  - 不允许在 `finalAnswer` 阶段把早先的 `tool_use` reasoning 回退吸收到 final response
- `assistantPlannerMessage` / `assistantToolCall` / `assistantQuestionPrompt` / `toolExecutionStarted` / `toolResult`：
  - 构造 `ChatMessage`，按 processor 配置注入 `agentTurnId` / `traceTurnIdPayloadKey`
  - `dbHelper.insertMessage` + `messagesProvider.addMessage`
  - 按事件类型调整 `chatSendStateProvider.phase`
- `assistantToolConfirmation`：
  - 默认同上 + `phase = awaitingConfirmation`
  - 若 `onAssistantToolConfirmation` 存在，先 await hook（用于 trace 记录）
  - 设置 `hasPendingConfirmation = true`
- `userInteractionResult`：
  - 若 `onUserInteractionResult` 存在且返回 true：跳过默认
  - 否则默认 `addMessage` 新建
- `toolExecutionStarted`：
  - 若 `transformFirstToolExecution` 存在且返回 true：跳过默认（hook 自己做 replaceMessage）
  - 否则默认 `addMessage` 新建
- `assistantTextDelta`：
  - 懒创建 assistant placeholder
  - 懒创建 `AssistantStreamOutputBuffer`
  - `onDelta(event.content ?? '')`
  - `phase = streamingResponse`
- `finalAnswer`：
  - 若存在 placeholder，先 finalize buffer 并移除该 placeholder
  - 始终 insert 一条新的 completed 最终回答消息
  - dispose buffer
  - `phase = idle`
  - 调用 `onFinalAnswer` hook（用于 trace + scheduleAutoSummary）
- `toolError`：走 `_appendToolResultMessage`，payload 用 `_buildToolFailurePayload`

### 三个调用点的最终形态

**`sendMessage` 路径**：

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
      traceRecorder.record(/* sendDone with awaitingConfirmation */);
    },
  ),
);
// 订阅 harness.runTurn(...) → processor.handle(event)
```

**`submitQuestionAnswers` 路径**：

```dart
final processor = AgentEventProcessor(
  ref: _ref,
  groupId: currentGroupId,
  traceTurnId: traceTurnId,
  agentTurnId: turnId,
  hooks: AgentEventHooks(
    onUserInteractionResult: (event) async {
      // 替换原 ask-prompt 消息，而不是新建
      final resultMessage = message.copyWith(...);
      _ref.read(messagesProvider.notifier).replaceMessage(resultMessage);
      await dbHelper.updateStructuredMessage(...);
      return true; // 跳过默认
    },
  ),
);
```

**`_resumeAgentLoopConfirmation` 路径**：

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
      // 替换原 confirmation 消息为 running 状态
      final runningMessage = sourceMessage.copyWith(...);
      _ref.read(messagesProvider.notifier).replaceMessage(runningMessage);
      await dbHelper.updateStructuredMessage(...);
      return true;
    },
  ),
);
// 结束后读 processor.hasPendingConfirmation 决定 phase
```

### 状态管理

- `assistantMessageId` / `assistantMessage` / `assistantStreamBuffer` 作为 processor 实例状态持有
- `hasPendingConfirmation` 作为 processor 内部 bool，外层通过 getter 读取
- `dispose` 负责取消 buffer、标记 processor 为终结态（防止误用）

### streamSubscriptionProvider 一致化

借这次重构统一：三个路径都走同样的注册 / finally 清理模板（`_resumeAgentLoopConfirmation` 之前没做注册会导致外部取消失效，应对齐）。

## 兼容 / 迁移风险

1. **事件处理顺序与异步时序**。当前使用 `asyncMap(...).listen(...)`，processor 内所有 handle 必须保持 await 顺序。迁移时 `processor.handle(event)` 必须在外层 `asyncMap` / `await for` 里 await。
2. **message 插入顺序**。DB insert → state addMessage 的顺序不能反。processor 内部保持原顺序。
3. **trace 记录点**。必须保持现有记录语义。hook 用来承接位置敏感的 trace（finalAnswer / toolConfirmation）。
4. **phase 收尾**。`_resumeAgentLoopConfirmation` 的 `hasPendingConfirmation` 决策迁移到 processor getter；外层只调 `setPhase` 一次。
5. **测试覆盖**。需要先补齐三路径集成测试，再改码。

## 验证路径

- `flutter test test/providers/` / `test/controllers/`（现有 + 新增）
- `flutter analyze` 零 warning
- 真机冒烟：
  - 普通发送 → 完成
  - 发送 → 工具 awaitConfirm → 确认 → 继续
  - 发送 → ask user question → 回答 → 继续
  - 发送 → 中途 cancel
  - 发送 → 工具失败
