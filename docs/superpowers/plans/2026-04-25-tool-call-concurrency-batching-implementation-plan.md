# Tool Call 并发批次调度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为一轮 planner decision 中的多个 tool call 引入“连续只读工具并发、写工具串行”的批次化调度，并提供最大并发度 10 的有限并发执行。

**Architecture:** 新增 decision 级 `DecisionToolCallExecutor`，专门处理一次 planner decision 中的多个 tool requests；`TurnHarness` 保留 turn loop 主控，只负责把本轮 toolCalls 交给执行器并根据执行摘要决定下一步。工具是否可并发由 `ToolDefinition.isConcurrencySafe` 声明；批次之间串行，批内有限并发，单个失败不影响同批其他任务。

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test

---

## File Boundaries

### Modify

- `lib/models/tool/tool_definition.dart`
  - 为工具定义补充 `isConcurrencySafe` 元数据，默认保守为 `false`。
- `lib/services/decision_tool_call_executor.dart`
  - 实现 decision 级 tool call 执行器、批次切分、批内有限并发执行与本轮执行摘要。
- `lib/services/turn_harness.dart`
  - 改为委托 decision 级执行器处理本轮 tool requests，并基于执行摘要判断是否继续 turn loop。
- `lib/tools/handlers/read_tool_handler.dart`
  - 显式声明 `isConcurrencySafe: true`。
- `lib/tools/handlers/list_directory_tool_handler.dart`
  - 显式声明 `isConcurrencySafe: true`。
- `lib/tools/handlers/grep_tool_handler.dart`
  - 显式声明 `isConcurrencySafe: true`。
- `lib/tools/handlers/glob_tool_handler.dart`
  - 显式声明 `isConcurrencySafe: true`。
- `lib/tools/handlers/web_search_tool_handler.dart`
  - 显式声明 `isConcurrencySafe: true`。
- `lib/tools/handlers/fetch_webpage_tool_handler.dart`
  - 显式声明 `isConcurrencySafe: true`。
- 写工具与交互工具对应 handler
  - 显式声明 `isConcurrencySafe: false`，避免默认值漂移时语义不清。
- `test/services/turn_harness_test.dart`
  - 覆盖 `TurnHarness` 与 decision 级执行器的集成、批后停止判断与回归行为。
- `test/services/decision_tool_call_executor_test.dart`
  - 覆盖 batch 切分、并发上限、批内失败独立与写工具隔离。
- `README.md`
  - 如需补充 agent loop / tool execution 行为说明，则用一句话更新“只读工具可能并发执行”。
- `AGENTS.md`
  - 如并发能力成为新团队约束，再补“工具需声明 `isConcurrencySafe`”。

### Optional Review

- `lib/repositories/chat_turn_step_repository.dart`
  - 确认并发完成多个 step 时没有隐藏的顺序假设。
- `lib/repositories/chat_event_repository.dart`
  - 确认并发追加 event 不会破坏 sequence 生成语义。

---

### Task 1: 为工具定义增加并发安全元数据

**Files:**
- Modify: `lib/models/tool/tool_definition.dart`
- Test: `test/services/turn_harness_test.dart`

- [ ] **Step 1: 写一个失败测试，锁定默认工具为非并发安全**

在 `turn_harness_test.dart` 新增最小测试样例，确保未显式声明时不会被归入并发批。

```dart
test('tool definition defaults to non-concurrency-safe', () {
  const definition = ToolDefinition(
    name: 'demo_tool',
    title: 'Demo',
  );

  expect(definition.isConcurrencySafe, isFalse);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'tool definition defaults to non-concurrency-safe'
```

Expected: FAIL because `ToolDefinition` does not yet expose `isConcurrencySafe`.

- [ ] **Step 3: 在 `ToolDefinition` 中加入字段**

实现最小字段与注释：

```dart
/// Whether multiple invocations of this tool can run in parallel within the
/// same planner decision without relying on shared mutable state ordering.
final bool isConcurrencySafe;
```

构造器默认值：

```dart
this.isConcurrencySafe = false,
```

- [ ] **Step 4: 重新运行单测确认通过**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'tool definition defaults to non-concurrency-safe'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/tool/tool_definition.dart test/services/turn_harness_test.dart
git commit -m "refactor: add tool concurrency safety metadata"
```

---

### Task 2: 为现有工具显式标注并发能力

**Files:**
- Modify: `lib/tools/handlers/read_tool_handler.dart`
- Modify: `lib/tools/handlers/list_directory_tool_handler.dart`
- Modify: `lib/tools/handlers/grep_tool_handler.dart`
- Modify: `lib/tools/handlers/glob_tool_handler.dart`
- Modify: `lib/tools/handlers/web_search_tool_handler.dart`
- Modify: `lib/tools/handlers/fetch_webpage_tool_handler.dart`
- Modify: 写工具 / 交互工具 handler

- [ ] **Step 1: 写一个失败测试，锁定只读工具为并发安全**

在 `turn_harness_test.dart` 或对应 handler test 中加一条最小断言：

```dart
test('read-oriented tools are marked concurrency-safe', () {
  expect(ReadToolHandler().definition.isConcurrencySafe, isTrue);
  expect(ListDirectoryToolHandler().definition.isConcurrencySafe, isTrue);
  expect(GrepToolHandler().definition.isConcurrencySafe, isTrue);
  expect(GlobToolHandler().definition.isConcurrencySafe, isTrue);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'read-oriented tools are marked concurrency-safe'
```

Expected: FAIL.

- [ ] **Step 3: 在各 handler 的 `ToolDefinition` 上声明 `isConcurrencySafe`**

对只读工具：

```dart
isConcurrencySafe: true,
```

对写工具、提醒、用户交互工具：

```dart
isConcurrencySafe: false,
```

- [ ] **Step 4: 重跑测试确认通过**

Run the same test command and expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/tools/handlers
git commit -m "refactor: classify tools by concurrency safety"
```

---

### Task 3: 新增 decision 级执行器骨架与结果摘要

**Files:**
- Create: `lib/services/decision_tool_call_executor.dart`
- Create: `test/services/decision_tool_call_executor_test.dart`
- Modify: `lib/services/turn_harness.dart`

- [ ] **Step 1: 写失败测试，锁定 `TurnHarness` 会把一轮 tool decision 委托给执行器**

```dart
test('turn harness delegates tool decisions to decision executor', () async {
  final fakeExecutor = _FakeDecisionToolCallExecutor();
  final harness = _buildHarness(decisionExecutor: fakeExecutor);

  await harness.runTurn(
    turn: _turnWithToolDecision(),
    config: ChatConfig(systemPrompt: ''),
  ).toList();

  expect(fakeExecutor.executeCalls, hasLength(1));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'turn harness delegates tool decisions to decision executor'
```

Expected: FAIL because there is no decision executor abstraction yet.

- [ ] **Step 3: 新建执行器接口与最小返回摘要**

在新文件中定义：

```dart
class DecisionToolExecutionSummary {
  final bool enteredAwaitingConfirmation;
  final bool enteredAwaitingUserInteraction;
  final bool hasFailures;
  final bool shouldStopFurtherExecution;
  final int executedToolCount;
}

abstract class DecisionToolCallExecutor {
  Stream<ChatEvent> executeDecisionToolCalls({...});
}
```

如果流式接口不方便，也可以让执行器返回：

```dart
class DecisionToolExecutionResult {
  final List<ChatEvent> emittedEvents;
  final DecisionToolExecutionSummary summary;
}
```

但必须保持“decision 级输入 / decision 级输出”的边界。

- [ ] **Step 4: 在 `TurnHarness` 中完成最小接线**

先只做到：

- `TurnHarness` 将本轮 `toolCalls` 交给执行器
- 继续保留旧行为作为执行器内部实现

- [ ] **Step 5: 重跑测试确认通过**

Run the same test command and expect PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/decision_tool_call_executor.dart lib/services/turn_harness.dart test/services/turn_harness_test.dart test/services/decision_tool_call_executor_test.dart
git commit -m "refactor: introduce decision-level tool call executor"
```

---

### Task 4: 在 decision 执行器中实现 batch 切分

**Files:**
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `test/services/decision_tool_call_executor_test.dart`

- [ ] **Step 1: 写失败测试，锁定批次切分结果**

新增一个纯切分层测试：

```dart
test('groups consecutive concurrency-safe tools into batches', () {
  final executor = _buildDecisionExecutorForBatching();
  final batches = executor.debugBuildBatches([
    _toolCall('Read'),
    _toolCall('Grep'),
    _toolCall('Write'),
    _toolCall('Read'),
    _toolCall('Glob'),
  ]);

  expect(
    batches.map((batch) => batch.toolCalls.map((call) => call.toolName).toList()),
    [
      ['Read', 'Grep'],
      ['Write'],
      ['Read', 'Glob'],
    ],
  );
  expect(batches.map((batch) => batch.isConcurrent), [true, false, true]);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'groups consecutive concurrency-safe tools into batches'
```

Expected: FAIL because batching helpers do not exist yet.

- [ ] **Step 3: 在 decision 执行器中新增轻量批次结构和切分方法**

实现最小结构：

```dart
class _ToolExecutionBatch {
  final List<ModelToolCall> toolCalls;
  final bool isConcurrent;
}
```

以及切分方法：

```dart
List<_ToolExecutionBatch> _buildExecutionBatches(List<ModelToolCall> toolCalls)
```

切分规则严格按 spec：

- 连续 `isConcurrencySafe == true` 聚合
- `false` 单独成批

- [ ] **Step 4: 重跑测试确认通过**

Run the same test command and expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/decision_tool_call_executor.dart test/services/decision_tool_call_executor_test.dart
git commit -m "refactor: batch decision tool calls by concurrency safety"
```

---

### Task 5: 实现并发安全 batch 的有限并发执行

**Files:**
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `test/services/decision_tool_call_executor_test.dart`

- [ ] **Step 1: 写失败测试，锁定并发批不会超过最大并发度**

新增一个带 gate 的假 tool executor 测试：

```dart
test('concurrent-safe batch respects max concurrency of 10', () async {
  final tracker = _ConcurrentExecutionTracker();
  final executor = _buildDecisionExecutor(
    maxConcurrentToolCalls: 10,
    toolExecutor: tracker.executor,
  );

  await executor.executeDecisionToolCalls(
    turn: _turnWithManyConcurrentReads(25),
    decision: _decisionWithManyConcurrentReads(25),
    config: ChatConfig(systemPrompt: ''),
  ).drain();

  expect(tracker.maxObservedConcurrency, lessThanOrEqualTo(10));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'concurrent-safe batch respects max concurrency of 10'
```

Expected: FAIL.

- [ ] **Step 3: 在 decision 执行器中加入批内有限并发执行器**

新增一个最小执行方法：

```dart
Future<void> _runConcurrentBatch({
  required _ToolExecutionBatch batch,
  required ChatTurn turn,
  required ChatConfig config,
})
```

用补位式并发执行：

- 启动最多 10 个 futures
- 每完成一个补一个
- 直到全部结束

- [ ] **Step 4: 保持单工具执行单元复用**

不要在并发路径里重写 tool 生命周期。
继续复用单任务执行函数，只把它包进批内调度。

- [ ] **Step 5: 重跑并发上限测试确认通过**

Run the same test command and expect PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/decision_tool_call_executor.dart test/services/decision_tool_call_executor_test.dart
git commit -m "feat: add bounded concurrent execution for safe tool batches"
```

---

### Task 6: 保证批内失败独立，不影响其他工具

**Files:**
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `test/services/decision_tool_call_executor_test.dart`

- [ ] **Step 1: 写失败测试，锁定单个只读工具失败不影响同批其他工具**

```dart
test('failure in one concurrent-safe tool does not stop other tools in the same batch', () async {
  final executor = _buildDecisionExecutorWithBatchResults([
    _failedTool('Read', 'file_not_found'),
    _successfulTool('Grep', 'matched'),
    _successfulTool('Glob', 'files'),
  ]);

  final events = await executor.executeDecisionToolCalls(
    turn: _turnForConcurrentBatch(),
    decision: _decisionForConcurrentBatch(),
    config: ChatConfig(systemPrompt: ''),
  ).toList();

  expect(events.where((e) => e.eventType == ChatEventType.toolError), hasLength(1));
  expect(events.where((e) => e.eventType == ChatEventType.toolResult), hasLength(2));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'failure in one concurrent-safe tool does not stop other tools in the same batch'
```

Expected: FAIL.

- [ ] **Step 3: 调整并发批收口逻辑**

确保：

- 单任务失败只更新自己的 step 和 event
- 不取消同批其他 futures
- 不阻止队列中后续任务启动

- [ ] **Step 4: 重跑测试确认通过**

Run the same test command and expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/decision_tool_call_executor.dart test/services/decision_tool_call_executor_test.dart
git commit -m "test: preserve tool independence within concurrent batches"
```

---

### Task 7: 保持批间串行与写工具隔离

**Files:**
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `test/services/decision_tool_call_executor_test.dart`

- [ ] **Step 1: 写失败测试，锁定写工具前后批次不会交错**

```dart
test('write tool remains isolated between concurrent read batches', () async {
  final trace = <String>[];
  final executor = _buildTracingDecisionExecutor(trace);

  await executor.executeDecisionToolCalls(
    turn: _turnForReadWriteReadSequence(),
    decision: _decisionForReadWriteReadSequence(),
    config: ChatConfig(systemPrompt: ''),
  ).drain();

  expect(
    trace,
    [
      'start:ReadA',
      'start:ReadB',
      'done:ReadA',
      'done:ReadB',
      'start:WriteC',
      'done:WriteC',
      'start:ReadD',
      'start:ReadE',
    ],
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'write tool remains isolated between concurrent read batches'
```

Expected: FAIL.

- [ ] **Step 3: 在 decision 执行器中改成“逐 batch 执行”**

在执行器内部把当前单个 tool call 逐项执行改成：

```dart
for (final batch in _buildExecutionBatches(decision.toolCalls)) { ... }
```

并确保：

- 并发 batch 全部结束后才进入下一个 batch
- 写工具 batch 只包含单个工具

- [ ] **Step 4: 重跑测试确认通过**

Run the same test command and expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/decision_tool_call_executor.dart test/services/decision_tool_call_executor_test.dart
git commit -m "feat: execute decision tool calls batch-by-batch"
```

---

### Task 8: `TurnHarness` 基于执行摘要做批后终止判断与文档收尾

**Files:**
- Modify: `lib/services/decision_tool_call_executor.dart`
- Modify: `lib/services/turn_harness.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`（如需要）
- Test: `test/services/turn_harness_test.dart`

- [ ] **Step 1: 写失败测试，锁定某批结束后 turn 终态会阻止后续批次**

```dart
test('turn harness stops after executor reports awaiting confirmation', () async {
  final executor = _FakeDecisionToolCallExecutor(
    summary: DecisionToolExecutionSummary(
      enteredAwaitingConfirmation: true,
      shouldStopFurtherExecution: true,
      executedToolCount: 2,
    ),
  );
  final harness = _buildHarness(decisionExecutor: executor);

  await harness.runTurn(
    turn: _turnWithToolDecision(),
    config: ChatConfig(systemPrompt: ''),
  ).toList();

  expect(executor.executeCalls, hasLength(1));
  expect(await harness.debugShouldContinueAfterToolDecision(), isFalse);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
flutter test test/services/turn_harness_test.dart --plain-name 'later batches do not run after turn becomes awaiting confirmation'
```

Expected: FAIL.

- [ ] **Step 3: 在 `TurnHarness` 中基于执行摘要统一判断后续控制流**

保留现有停止条件，但把检查点从“单个 tool call 之后”扩展为“每批结束后”。

- [ ] **Step 4: 更新 README / AGENTS（仅在需要时）**

最小文案建议：

- README：只读工具在同一 decision 内可能并发执行
- AGENTS：新工具若涉及 turn loop 调度，需要明确声明 `isConcurrencySafe`

- [ ] **Step 5: 运行核心测试集**

Run:

```bash
flutter test test/services/turn_harness_test.dart test/providers/chat_controller_tool_flow_test.dart
flutter test test/services/decision_tool_call_executor_test.dart
flutter analyze lib/models/tool/tool_definition.dart lib/services/decision_tool_call_executor.dart lib/services/turn_harness.dart test/services/turn_harness_test.dart test/services/decision_tool_call_executor_test.dart
```

Expected:

- tests PASS
- analyze PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/decision_tool_call_executor.dart lib/services/turn_harness.dart test/services/turn_harness_test.dart test/services/decision_tool_call_executor_test.dart README.md AGENTS.md
git commit -m "feat: add concurrent batching for safe tool calls"
```
