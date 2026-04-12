# Tool Runtime And Chat Flow Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有分散的 tool call 运行时重构为基于 `ToolHandler` 的组件化体系，并为后续聊天发送链路拆分预留清晰边界。

**Architecture:** 第一阶段只重构 tool 执行侧，不改 UI 展示协议。通过引入 `ToolHandler`、升级 `ToolRegistry`、收口 `ToolOrchestratorService` 的通用编排职责，把单个 tool 的 definition、参数归一化、执行和上下文构建迁移到 handler 内部。第二阶段在新 tool 边界稳定后，再拆分 `ChatController` 的发送事务与状态域。

**Tech Stack:** Flutter, Dart, flutter_riverpod, existing chat/tool pipeline, Flutter test

---

## File Map

**Create:**

- `lib/tools/core/tool_handler.dart`：定义统一的 `ToolHandler` 接口
- `lib/tools/core/tool_argument_resolution.dart`：定义参数归一化结果
- `lib/tools/core/tool_execution_context.dart`：定义 tool 执行上下文
- `lib/tools/core/tool_runtime_registry.dart`：注册并查找 `ToolHandler`
- `lib/tools/adapters/tool_host_adapters.dart`：收拢宿主 adapter 依赖
- `lib/tools/handlers/web_search_tool_handler.dart`：`web_search` handler
- `lib/tools/handlers/create_reminder_tool_handler.dart`：`create_reminder` handler
- `lib/tools/handlers/create_calendar_event_tool_handler.dart`：`create_calendar_event` handler
- `test/tools/handlers/web_search_tool_handler_test.dart`
- `test/tools/handlers/create_reminder_tool_handler_test.dart`
- `test/tools/handlers/create_calendar_event_tool_handler_test.dart`
- `test/tools/core/tool_runtime_registry_test.dart`

**Modify:**

- `lib/services/tool_registry.dart`：过渡为 definition/handler 兼容入口，最终委托给新 registry
- `lib/services/tool_executor.dart`：从中心分发器逐步退化为 adapter 载体
- `lib/services/tool_decision_service.dart`：删除 tool 专属参数校验和归一化逻辑，只保留决策
- `lib/services/tool_orchestrator_service.dart`：改为基于 `ToolHandler` 的通用编排
- `lib/services/tool_call_service.dart`：继续保留 facade，但内部切换到新运行时
- `lib/main.dart`：注册 runtime registry 和 host adapters
- `test/services/tool_decision_service_test.dart`
- `test/services/tool_orchestrator_service_test.dart`
- `test/services/tool_executor_test.dart`

**Later Modify (Phase 2 / Chat Flow):**

- `lib/providers/chat_providers.dart`
- `lib/services/chat_service.dart`
- `docs/README` 或项目 README 对消息发送链路的说明

---

### Task 1: Define Tool Handler Runtime Core

**Files:**

- Create: `lib/tools/core/tool_handler.dart`
- Create: `lib/tools/core/tool_argument_resolution.dart`
- Create: `lib/tools/core/tool_execution_context.dart`
- Create: `lib/tools/core/tool_runtime_registry.dart`
- Create: `lib/tools/adapters/tool_host_adapters.dart`
- Test: `test/tools/core/tool_runtime_registry_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('registry returns registered handler by tool name', () {
  final registry = ToolRuntimeRegistry(
    handlers: [
      FakeToolHandler(toolName: 'web_search'),
    ],
  );

  expect(registry.findHandler('web_search'), isNotNull);
  expect(registry.findHandler('missing_tool'), isNull);
});

test('registry exposes all tool definitions for decision service', () {
  final registry = ToolRuntimeRegistry(
    handlers: [
      FakeToolHandler(toolName: 'web_search'),
      FakeToolHandler(toolName: 'create_reminder'),
    ],
  );

  expect(
    registry.getAllDefinitions().map((item) => item.name),
    ['web_search', 'create_reminder'],
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tools/core/tool_runtime_registry_test.dart`

Expected: FAIL because runtime core types do not exist yet

- [ ] **Step 3: Write minimal implementation**

实现：

- `ToolHandler` 接口
- `ToolArgumentResolution`
- `ToolExecutionContext`
- `ToolHostAdapters`
- `ToolRuntimeRegistry`

接口最小要求：

```dart
abstract class ToolHandler {
  ToolDefinition get definition;

  Future<ToolArgumentResolution> normalizeArguments({...});

  Future<ToolResult> execute(ToolExecutionContext context);

  List<ChatMessage> buildContextMessages({...});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tools/core/tool_runtime_registry_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tools/core lib/tools/adapters/tool_host_adapters.dart test/tools/core/tool_runtime_registry_test.dart
git commit -m "feat: add tool handler runtime core"
```

### Task 2: Migrate Web Search To ToolHandler

**Files:**

- Create: `lib/tools/handlers/web_search_tool_handler.dart`
- Modify: `lib/services/tool_executor.dart`
- Test: `test/tools/handlers/web_search_tool_handler_test.dart`
- Test: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('web search handler normalizes maxResults and executes search adapter', () async {
  final handler = WebSearchToolHandler(
    webSearcher: ({required query, maxResults}) async => ToolResult(
      toolName: 'web_search',
      status: ToolExecutionStatus.success,
      summary: '已执行联网搜索',
      data: {'query': query, 'maxResults': maxResults},
    ),
  );

  final resolution = await handler.normalizeArguments(
    rawArguments: {'query': 'OpenAI 最新消息'},
    userMessage: '请搜索 OpenAI 最新消息',
    history: const [],
    now: DateTime(2026, 4, 12),
  );

  expect(resolution.isValid, isTrue);
  expect(resolution.normalizedArguments['maxResults'], 5);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

- `flutter test test/tools/handlers/web_search_tool_handler_test.dart`
- `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: FAIL because `WebSearchToolHandler` does not exist and orchestrator still uses old branching

- [ ] **Step 3: Write minimal implementation**

实现：

- `WebSearchToolHandler`
- 参数校验与默认值归一化
- `buildContextMessages()` 中生成联网搜索上下文
- `ToolOrchestratorService` 增加从 registry 获取 handler 的通路

要求：

- 仍保持现有 `ToolResult` 结构不变
- 仍保持现有 trace 事件顺序不变
- 不在 orchestrator 中保留 `web_search` 的专属分支

- [ ] **Step 4: Run test to verify it passes**

Run:

- `flutter test test/tools/handlers/web_search_tool_handler_test.dart`
- `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tools/handlers/web_search_tool_handler.dart lib/services/tool_executor.dart lib/services/tool_orchestrator_service.dart test/tools/handlers/web_search_tool_handler_test.dart test/services/tool_orchestrator_service_test.dart
git commit -m "feat: migrate web search to tool handler"
```

### Task 3: Migrate Reminder And Calendar Tools To ToolHandlers

**Files:**

- Create: `lib/tools/handlers/create_reminder_tool_handler.dart`
- Create: `lib/tools/handlers/create_calendar_event_tool_handler.dart`
- Modify: `lib/services/tool_decision_service.dart`
- Modify: `lib/services/tool_orchestrator_service.dart`
- Test: `test/tools/handlers/create_reminder_tool_handler_test.dart`
- Test: `test/tools/handlers/create_calendar_event_tool_handler_test.dart`
- Test: `test/services/tool_decision_service_test.dart`
- Test: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('reminder handler normalizes relative time arguments from user intent', () async {
  final handler = CreateReminderToolHandler(
    reminderCreator: ({required title, dueAt, note}) async => ToolResult(
      toolName: 'create_reminder',
      status: ToolExecutionStatus.success,
      summary: 'ok',
      data: {'dueAt': dueAt},
    ),
  );

  final resolution = await handler.normalizeArguments(
    rawArguments: {'title': '交周报', 'dueAt': '2025-02-14T20:00:00+08:00'},
    userMessage: '明天晚上8点提醒我交周报',
    history: const [],
    now: DateTime(2025, 2, 13, 9),
  );

  expect(resolution.isValid, isTrue);
  expect(resolution.normalizedArguments['dueAt'], '2025-02-14T20:00:00+08:00');
});
```

```dart
test('decision service no longer rejects reminder arguments itself', () async {
  // 决策服务只返回 toolName + rawArguments，不做 reminder 专属校验。
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

- `flutter test test/tools/handlers/create_reminder_tool_handler_test.dart`
- `flutter test test/tools/handlers/create_calendar_event_tool_handler_test.dart`
- `flutter test test/services/tool_decision_service_test.dart`
- `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: FAIL because归一化逻辑仍留在 `ToolDecisionService`

- [ ] **Step 3: Write minimal implementation**

实现：

- `CreateReminderToolHandler`
- `CreateCalendarEventToolHandler`
- 将 reminder/calendar 的参数校验和相对时间归一化，从 `ToolDecisionService` 迁移到 handler
- `ToolDecisionService` 只保留通用 JSON 解析、unknown tool 判断和基本意图过滤

- [ ] **Step 4: Run test to verify it passes**

Run:

- `flutter test test/tools/handlers/create_reminder_tool_handler_test.dart`
- `flutter test test/tools/handlers/create_calendar_event_tool_handler_test.dart`
- `flutter test test/services/tool_decision_service_test.dart`
- `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/tools/handlers/create_reminder_tool_handler.dart lib/tools/handlers/create_calendar_event_tool_handler.dart lib/services/tool_decision_service.dart lib/services/tool_orchestrator_service.dart test/tools/handlers/create_reminder_tool_handler_test.dart test/tools/handlers/create_calendar_event_tool_handler_test.dart test/services/tool_decision_service_test.dart test/services/tool_orchestrator_service_test.dart
git commit -m "feat: migrate reminder and calendar tool handlers"
```

### Task 4: Replace Tool Switching With Registry-Driven Orchestration

**Files:**

- Modify: `lib/services/tool_registry.dart`
- Modify: `lib/services/tool_orchestrator_service.dart`
- Modify: `lib/services/tool_call_service.dart`
- Modify: `lib/main.dart`
- Test: `test/services/tool_orchestrator_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('orchestrator resolves handlers entirely from runtime registry', () async {
  final registry = ToolRuntimeRegistry(
    handlers: [FakeToolHandler(toolName: 'web_search')],
  );
  final service = ToolOrchestratorService(
    runtimeRegistry: registry,
    ...
  );

  final result = await service.prepareToolContext(...);

  expect(result.toolInvocation?.toolName, 'web_search');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: FAIL because orchestrator still depends on internal switch-based dispatch

- [ ] **Step 3: Write minimal implementation**

实现：

- `ToolOrchestratorService` 完全基于 runtime registry 调用 handler
- `ToolRegistry` 兼容现有 definition 访问，但内部从 handler 派生 definition
- `ToolCallService` 继续保留 facade，内部切换到新 runtime
- `main.dart` 中注册 handler 列表和 host adapters

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/tool_registry.dart lib/services/tool_orchestrator_service.dart lib/services/tool_call_service.dart lib/main.dart test/services/tool_orchestrator_service_test.dart
git commit -m "refactor: use registry-driven tool orchestration"
```

### Task 5: Clean Up Legacy Tool Execution Paths

**Files:**

- Modify: `lib/services/tool_executor.dart`
- Modify: `lib/services/tool_decision_service.dart`
- Modify: `lib/services/tool_registry.dart`
- Test: `test/services/tool_executor_test.dart`
- Test: `test/services/tool_decision_service_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('tool executor only exposes host adapter methods after migration', () {
  // 验证不再通过 ToolExecutor 做按名称分发。
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

- `flutter test test/services/tool_executor_test.dart`
- `flutter test test/services/tool_decision_service_test.dart`

Expected: FAIL because legacy responsibilities are still present

- [ ] **Step 3: Write minimal implementation**

清理：

- `ToolExecutor` 中与名称分发强相关的残余职责
- `ToolDecisionService` 中与单个 tool 绑定的专属逻辑
- `ToolRegistry` 中只为旧实现保留的过时接口

要求：

- 不破坏现有 public result shape
- trace 顺序测试继续保持通过

- [ ] **Step 4: Run test to verify it passes**

Run:

- `flutter test test/services/tool_executor_test.dart`
- `flutter test test/services/tool_decision_service_test.dart`
- `flutter test test/services/tool_orchestrator_service_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/tool_executor.dart lib/services/tool_decision_service.dart lib/services/tool_registry.dart test/services/tool_executor_test.dart test/services/tool_decision_service_test.dart test/services/tool_orchestrator_service_test.dart
git commit -m "refactor: remove legacy tool execution paths"
```

### Task 6: Prepare Chat Send Flow Decomposition Boundary

**Files:**

- Modify: `lib/providers/chat_providers.dart`
- Create: `docs/superpowers/specs/2026-04-12-tool-runtime-and-chat-flow-refactor-design.md`
- Test: `test/providers/chat_controller_tool_flow_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('chat controller delegates send transaction boundary to a dedicated coordinator', () async {
  // 本任务先建立边界，而不完整拆分实现。
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/chat_controller_tool_flow_test.dart`

Expected: FAIL because send transaction is still fully embedded in `ChatController`

- [ ] **Step 3: Write minimal implementation**

本任务只做“准备边界”，不做完整发送链路重写：

- 提取 `ChatController` 内与 send transaction 强相关的私有帮助方法
- 让 send transaction 逻辑形成可迁移结构
- 保持对现有 UI 和测试行为零回归

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/chat_controller_tool_flow_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/chat_providers.dart test/providers/chat_controller_tool_flow_test.dart
git commit -m "refactor: prepare chat send coordinator boundary"
```

### Task 7: Focused Verification

**Files:**

- Test: `test/tools/core/tool_runtime_registry_test.dart`
- Test: `test/tools/handlers/web_search_tool_handler_test.dart`
- Test: `test/tools/handlers/create_reminder_tool_handler_test.dart`
- Test: `test/tools/handlers/create_calendar_event_tool_handler_test.dart`
- Test: `test/services/tool_decision_service_test.dart`
- Test: `test/services/tool_orchestrator_service_test.dart`
- Test: `test/services/tool_executor_test.dart`
- Test: `test/providers/chat_controller_tool_flow_test.dart`

- [ ] **Step 1: Run focused tool runtime verification**

Run:

```bash
flutter test \
  test/tools/core/tool_runtime_registry_test.dart \
  test/tools/handlers/web_search_tool_handler_test.dart \
  test/tools/handlers/create_reminder_tool_handler_test.dart \
  test/tools/handlers/create_calendar_event_tool_handler_test.dart \
  test/services/tool_decision_service_test.dart \
  test/services/tool_orchestrator_service_test.dart \
  test/services/tool_executor_test.dart \
  test/providers/chat_controller_tool_flow_test.dart
```

Expected: PASS

- [ ] **Step 2: Run static analysis**

Run:

```bash
flutter analyze \
  lib/main.dart \
  lib/services/tool_call_service.dart \
  lib/services/tool_decision_service.dart \
  lib/services/tool_orchestrator_service.dart \
  lib/services/tool_executor.dart \
  lib/services/tool_registry.dart \
  lib/tools/core \
  lib/tools/handlers \
  lib/tools/adapters \
  lib/providers/chat_providers.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Manual smoke verification**

Run app with existing local config and verify:

- `web_search` 仍能返回结构化上下文
- `create_reminder` 仍能走确认或白名单流程
- `create_calendar_event` 仍能正常执行
- trace 日志仍能串起 `turnId`

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "test: verify tool runtime refactor"
```

## Notes

- 本计划刻意将 UI 展示留在现有协议下，避免把 runtime 重构与界面重构耦合。
- `Task 6` 只做发送链路的边界准备，不在本计划中完成完整 `ChatSendCoordinator` 拆分。
- 若在实施中发现 `ToolRegistry` 与现有 `ToolDefinition` 使用面过广，可先保留兼容 facade，再在后续小任务里清理。
