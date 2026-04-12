# Chat Send Trace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为聊天发送主链路建立统一的 trace 追踪能力，让一次发送从用户提交到最终完成/失败都能用同一个 `turnId` 串起来排障。

**Architecture:** 采用轻量结构化 trace 方案，在现有 `Logger` 之上新增 `ChatTraceRecorder`，统一记录线性阶段事件而不是继续堆散落文本日志。第一阶段只覆盖发送主链路和 tool call 链路，输出到终端日志并保留最近一次发送的上下文摘要，后续可以平滑扩展到设置页调试面板。

**Tech Stack:** Flutter, Dart, flutter_riverpod, existing `Logger`, existing chat/tool pipeline

---

## File Map

**Create:**
- `lib/models/trace/chat_trace_event.dart`：定义 trace 事件模型、阶段枚举、状态枚举、序列化方法
- `lib/services/chat_trace_recorder.dart`：统一 trace 记录器，负责生成 `turnId`、记录事件、输出结构化日志
- `test/services/chat_trace_recorder_test.dart`：验证 trace 记录器输出和事件聚合行为

**Modify:**
- `lib/providers/chat_providers.dart`：在 `ChatController.sendMessage()` 与确认执行工具链路中创建并传递 `turnId`
- `lib/services/chat_service.dart`：记录上下文选择、保底上下文注入、LLM 发送开始/失败/完成
- `lib/services/tool_call_service.dart`：为 prepare/execute 链路补充 trace 透传
- `lib/services/tool_orchestrator_service.dart`：记录工具命中、确认策略、执行结果、上下文构建摘要
- `lib/services/tool_decision_service.dart`：记录工具决策开始、原始响应摘要、拒绝原因、归一化结果
- `lib/models/llm/base_llm.dart`：为发送/工具决策接口补充可选 `turnId` 或 trace 参数
- `lib/models/llm/configurable_http_llm.dart`：记录请求风格、模型名、请求摘要、首 token、流结束、失败状态
- `lib/models/llm/api_stream_parser.dart`：必要时补充首 token/流完成 trace 钩子
- `lib/utils/logger.dart`：若需要，补充结构化字段输出辅助方法
- `test/providers/chat_controller_tool_flow_test.dart`：验证 controller 会创建并透传 trace
- `test/services/tool_orchestrator_service_test.dart`：验证工具链路阶段事件
- `test/services/tool_decision_service_test.dart`：验证决策拒绝/命中事件摘要
- `test/services/chat_service_structured_output_test.dart`：补充发送链路 trace 断言

**Reference:**
- `lib/providers/chat_providers.dart`
- `lib/services/chat_service.dart`
- `lib/services/tool_call_service.dart`
- `lib/services/tool_orchestrator_service.dart`
- `lib/services/tool_decision_service.dart`
- `lib/models/llm/configurable_http_llm.dart`
- `lib/utils/logger.dart`

### Task 1: Define Trace Model And Recorder

**Files:**
- Create: `lib/models/trace/chat_trace_event.dart`
- Create: `lib/services/chat_trace_recorder.dart`
- Test: `test/services/chat_trace_recorder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('records ordered events for a single turn', () {
  final recorder = ChatTraceRecorder(logger: fakeLogger);

  recorder.record(
    turnId: 'turn-1',
    stage: ChatTraceStage.sendStart,
    status: ChatTraceStatus.started,
    summary: '开始发送',
  );
  recorder.record(
    turnId: 'turn-1',
    stage: ChatTraceStage.sendDone,
    status: ChatTraceStatus.success,
    summary: '发送完成',
  );

  expect(recorder.eventsForTurn('turn-1'), hasLength(2));
  expect(recorder.eventsForTurn('turn-1').first.stage, ChatTraceStage.sendStart);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/chat_trace_recorder_test.dart`
Expected: FAIL with missing `ChatTraceRecorder` / trace model types

- [ ] **Step 3: Write minimal implementation**

```dart
enum ChatTraceStage { sendStart, sendDone }
enum ChatTraceStatus { started, success, failure }

class ChatTraceEvent {
  final String turnId;
  final ChatTraceStage stage;
  final ChatTraceStatus status;
  final String summary;
}

class ChatTraceRecorder {
  void record(...) { ... }
  List<ChatTraceEvent> eventsForTurn(String turnId) { ... }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/chat_trace_recorder_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/trace/chat_trace_event.dart lib/services/chat_trace_recorder.dart test/services/chat_trace_recorder_test.dart
git commit -m "feat: add chat trace recorder"
```

### Task 2: Add Turn Trace Lifecycle In ChatController

**Files:**
- Modify: `lib/providers/chat_providers.dart`
- Test: `test/providers/chat_controller_tool_flow_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('sendMessage creates turn trace and records send lifecycle', () async {
  final recorder = FakeChatTraceRecorder();
  final container = createContainer(traceRecorder: recorder);

  await container.read(chatControllerProvider).sendMessage('测试消息');

  expect(recorder.events.any((e) => e.stage == ChatTraceStage.sendStart), isTrue);
  expect(recorder.events.any((e) => e.stage == ChatTraceStage.sendDone), isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/chat_controller_tool_flow_test.dart`
Expected: FAIL because controller does not create or emit trace events

- [ ] **Step 3: Write minimal implementation**

```dart
final turnId = chatTraceRecorder.newTurnId();
chatTraceRecorder.record(... sendStart ...);
chatTraceRecorder.record(... userMessagePersisted ...);
chatTraceRecorder.record(... sendDone/sendFailed ...);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/chat_controller_tool_flow_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/chat_providers.dart test/providers/chat_controller_tool_flow_test.dart
git commit -m "feat: trace chat controller send lifecycle"
```

### Task 3: Trace Tool Preparation And Tool Execution Path

**Files:**
- Modify: `lib/services/tool_call_service.dart`
- Modify: `lib/services/tool_decision_service.dart`
- Modify: `lib/services/tool_orchestrator_service.dart`
- Test: `test/services/tool_decision_service_test.dart`
- Test: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('web_search emits decision, execution and context events', () async {
  final recorder = FakeChatTraceRecorder();
  final service = createService(traceRecorder: recorder, ...);

  await service.prepareToolContext(...);

  expect(recorder.hasStage(ChatTraceStage.toolDecisionDone), isTrue);
  expect(recorder.hasStage(ChatTraceStage.toolExecuteDone), isTrue);
  expect(recorder.hasStage(ChatTraceStage.toolContextBuilt), isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/tool_decision_service_test.dart test/services/tool_orchestrator_service_test.dart`
Expected: FAIL because tool services do not emit trace events

- [ ] **Step 3: Write minimal implementation**

```dart
traceRecorder.record(... toolPrepareStart ...);
traceRecorder.record(... toolDecisionDone, data: {'toolName': ...} ...);
traceRecorder.record(... toolExecuteDone, data: {'status': ...} ...);
traceRecorder.record(... toolContextBuilt, data: {'contextLength': ...} ...);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/tool_decision_service_test.dart test/services/tool_orchestrator_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/tool_call_service.dart lib/services/tool_decision_service.dart lib/services/tool_orchestrator_service.dart test/services/tool_decision_service_test.dart test/services/tool_orchestrator_service_test.dart
git commit -m "feat: trace tool decision and execution flow"
```

### Task 4: Trace Context Selection And LLM Request Lifecycle

**Files:**
- Modify: `lib/services/chat_service.dart`
- Modify: `lib/models/llm/base_llm.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`
- Test: `test/services/chat_service_structured_output_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('sendMessageStream records context selection and llm lifecycle', () async {
  final recorder = FakeChatTraceRecorder();
  final llm = CapturingBaseLLM(traceRecorder: recorder);
  final service = ChatService(llm: llm, traceRecorder: recorder);

  await service.sendMessageStream('帮我总结', history, config).drain<void>();

  expect(recorder.hasStage(ChatTraceStage.contextSelected), isTrue);
  expect(recorder.hasStage(ChatTraceStage.llmRequestStart), isTrue);
  expect(recorder.hasStage(ChatTraceStage.llmFirstToken), isTrue);
  expect(recorder.hasStage(ChatTraceStage.llmDone), isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/chat_service_structured_output_test.dart`
Expected: FAIL because send/LLM lifecycle does not emit trace events

- [ ] **Step 3: Write minimal implementation**

```dart
traceRecorder.record(... contextSelected, data: {'historyCount': ..., 'selectedCount': ...} ...);
traceRecorder.record(... llmRequestStart, data: {'model': modelName, 'apiStyle': apiStyle} ...);
traceRecorder.record(... llmFirstToken ...);
traceRecorder.record(... llmDone ...);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/chat_service_structured_output_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/chat_service.dart lib/models/llm/base_llm.dart lib/models/llm/configurable_http_llm.dart lib/models/llm/api_stream_parser.dart test/services/chat_service_structured_output_test.dart
git commit -m "feat: trace chat context and llm lifecycle"
```

### Task 5: Normalize Structured Trace Logging Output

**Files:**
- Modify: `lib/utils/logger.dart`
- Modify: `lib/services/chat_trace_recorder.dart`
- Test: `test/services/chat_trace_recorder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('trace recorder emits structured preview-safe logs', () {
  final fakeLogger = FakeLogger();
  final recorder = ChatTraceRecorder(logger: fakeLogger);

  recorder.record(
    turnId: 'turn-1',
    stage: ChatTraceStage.llmRequestStart,
    status: ChatTraceStatus.started,
    summary: '开始请求',
    data: {'apiKey': 'secret', 'userMessagePreview': '很长的文本...'},
  );

  expect(fakeLogger.lastMessage, contains('turnId=turn-1'));
  expect(fakeLogger.lastMessage, isNot(contains('secret')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/chat_trace_recorder_test.dart`
Expected: FAIL because logger output is not structured or sensitive fields are not stripped

- [ ] **Step 3: Write minimal implementation**

```dart
String formatTraceEvent(ChatTraceEvent event) {
  // flatten fields and redact sensitive keys
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/chat_trace_recorder_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/utils/logger.dart lib/services/chat_trace_recorder.dart test/services/chat_trace_recorder_test.dart
git commit -m "feat: normalize structured trace logging"
```

### Task 6: Run Focused Verification And Capture A Sample Trace

**Files:**
- Modify: `test/providers/chat_controller_tool_flow_test.dart`
- Modify: `test/services/chat_service_structured_output_test.dart`
- Modify: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Add one end-to-end style assertion set for the full trace path**

```dart
expect(recorder.stagesForTurn(turnId), containsAllInOrder([
  ChatTraceStage.sendStart,
  ChatTraceStage.toolDecisionDone,
  ChatTraceStage.toolExecuteDone,
  ChatTraceStage.contextSelected,
  ChatTraceStage.llmRequestStart,
  ChatTraceStage.llmDone,
  ChatTraceStage.sendDone,
]));
```

- [ ] **Step 2: Run focused verification**

Run: `flutter test test/providers/chat_controller_tool_flow_test.dart test/services/chat_service_structured_output_test.dart test/services/tool_decision_service_test.dart test/services/tool_orchestrator_service_test.dart test/services/chat_trace_recorder_test.dart`
Expected: PASS

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/providers/chat_providers.dart lib/services/chat_service.dart lib/services/tool_call_service.dart lib/services/tool_decision_service.dart lib/services/tool_orchestrator_service.dart lib/models/llm/base_llm.dart lib/models/llm/configurable_http_llm.dart lib/models/llm/api_stream_parser.dart lib/models/trace/chat_trace_event.dart lib/services/chat_trace_recorder.dart lib/utils/logger.dart`
Expected: No issues found

- [ ] **Step 4: Manual smoke verification**

Run:
`flutter run -d chrome --web-hostname 127.0.0.1 --web-port 7357`

Manual check:
- 发送普通消息，确认日志包含完整 send trace
- 发送 `帮我搜索 OpenAI 最新消息`，确认日志包含 tool + context + llm trace
- 确认日志中不出现完整 API key 和完整网页正文

- [ ] **Step 5: Commit**

```bash
git add test/providers/chat_controller_tool_flow_test.dart test/services/chat_service_structured_output_test.dart test/services/tool_orchestrator_service_test.dart
git commit -m "test: verify chat send trace lifecycle"
```
