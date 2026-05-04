# Runtime Tool Call Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 planner/tool call 的流式参数增量以通用 runtime stream 形式向上层暴露，并让 `create_artifact` 首先消费这条能力，实现渐进式 artifact 渲染。

**Architecture:** LLM streaming 组装层继续负责最终 `ModelTurnDecision`，同时产出 runtime-only 的流式条目；上层通过 `kind` 分流 assistant/reasoning/tool-call 参数流，而不是靠工具字段语义猜测。`TurnHarness` 保持只关心最终决策，projection/UI 层消费 runtime stream entry 并为 `create_artifact` 提供渐进预览输入。  

**Tech Stack:** Flutter, `riverpod`, `webview_flutter`, existing LLM streaming/parser stack

---

### Task 1: 定义通用 runtime stream entry，并建立最小投影接口

**Files:**
- Create: `lib/models/chat/runtime_stream_entry.dart`
- Modify: `lib/models/chat/chat_timeline_projection.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Test: `test/models/chat/runtime_stream_entry_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('runtime stream entry exposes kind and raw text snapshot', () {
  final entry = RuntimeStreamEntry(
    turnId: '7_1',
    entryId: '7_1-tool-1',
    kind: RuntimeStreamEntryKind.toolCallArguments,
    providerCallId: 'call_1',
    toolName: 'create_artifact',
    createdAt: DateTime(2026, 5, 5, 10),
    updatedAt: DateTime(2026, 5, 5, 10),
    text: '{"source":"<div>',
  );

  expect(entry.kind, RuntimeStreamEntryKind.toolCallArguments);
  expect(entry.text, contains('<div>'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/models/chat/runtime_stream_entry_test.dart -r expanded`

Expected: fail because the runtime stream entry model does not exist yet.

- [ ] **Step 3: 最小实现**

```dart
// Add a small runtime-only model with:
// - turnId / entryId / kind / providerCallId / toolName / createdAt / updatedAt / text / payload
// - kind values: assistantText, reasoning, toolCallArguments
// Wire ChatTimelineProjection to carry an optional list of runtime entries.
// Add a Riverpod provider placeholder for the runtime stream snapshot.
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/models/chat/runtime_stream_entry_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/chat/runtime_stream_entry.dart lib/models/chat/chat_timeline_projection.dart lib/providers/chat_ui_providers.dart test/models/chat/runtime_stream_entry_test.dart
git commit -m "feat: add runtime stream entry model"
```

### Task 2: 让 LLM streaming 层上浮 runtime-only tool call 增量

**Files:**
- Modify: `lib/models/llm/streaming_planner_chunk.dart`
- Modify: `lib/models/llm/streaming_decision_accumulator.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Test: `test/models/llm/streaming_decision_accumulator_test.dart`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('streaming accumulator exposes runtime snapshots for tool call arguments', () {
  final accumulator = StreamingDecisionAccumulator();
  accumulator.consume(
    const StreamingPlannerChunk.toolCallStarted(
      providerCallId: 'call_1',
      toolName: 'create_artifact',
    ),
  );
  accumulator.consume(
    const StreamingPlannerChunk.toolCallArgumentsDelta(
      providerCallId: 'call_1',
      toolName: 'create_artifact',
      argumentsTextDelta: '{"source":"<div>',
    ),
  );

  final snapshots = accumulator.runtimeSnapshots();
  expect(snapshots.single.kind, RuntimeStreamEntryKind.toolCallArguments);
  expect(snapshots.single.toolName, 'create_artifact');
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/models/llm/streaming_decision_accumulator_test.dart -r expanded`

Expected: fail because accumulator does not yet expose runtime snapshots.

- [ ] **Step 3: 最小实现**

```dart
// Add runtime snapshot collection alongside the existing final decision state.
// Do not change buildDecision() semantics.
// Ensure ConfigurableHttpLLM can expose the latest runtime snapshot list from the streaming attempt result.
// Keep the final ModelTurnDecision path unchanged.
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/models/llm/streaming_decision_accumulator_test.dart test/models/llm/configurable_http_llm_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/llm/streaming_planner_chunk.dart lib/models/llm/streaming_decision_accumulator.dart lib/models/llm/configurable_http_llm.dart test/models/llm/streaming_decision_accumulator_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: surface runtime tool call streaming"
```

### Task 3: 让 projection/UI 消费 runtime stream entries

**Files:**
- Modify: `lib/services/chat_timeline_projection_service.dart`
- Modify: `lib/services/tool_presentation_block_projector.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/tool_renderers/create_artifact_tool_renderer.dart`
- Test: `test/services/chat_timeline_projection_service_test.dart`
- Test: `test/widgets/chat_timeline/chat_timeline_row_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('timeline projection includes runtime tool call entries before completion', () {
  // Build a projection snapshot with one runtime tool-call entry for create_artifact
  // and assert that the projection yields a visible artifact-related runtime block.
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart -r expanded`

Expected: fail because projection does not yet accept runtime stream entries.

- [ ] **Step 3: 最小实现**

```dart
// Extend the projection service to accept runtime stream entries.
// Convert runtime entries into presentation events or runtime blocks.
// Keep persisted transcript facts as the source of truth for completed tool/result history.
// Ensure create_artifact renderer can read rawArgumentsText from the runtime entry payload.
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart test/widgets/chat_timeline/chat_timeline_row_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/chat_timeline_projection_service.dart lib/services/tool_presentation_block_projector.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/widgets/tool_renderers/create_artifact_tool_renderer.dart test/services/chat_timeline_projection_service_test.dart test/widgets/chat_timeline/chat_timeline_row_test.dart
git commit -m "feat: project runtime tool call entries"
```

### Task 4: 实现 create_artifact 的渐进式渲染与节流

**Files:**
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Modify: `lib/tools/handlers/create_artifact_tool_handler.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`
- Test: `test/tools/handlers/create_artifact_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('artifact preview exposes throttled incremental refresh behavior', () {
  // Verify repeated partial source updates are coalesced and the preview keeps
  // the latest successful render while waiting for the next valid snapshot.
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart -r expanded`

Expected: fail because preview does not yet consume runtime tool-call snapshots.

- [ ] **Step 3: 最小实现**

```dart
// Add a small incremental refresh controller for create_artifact.
// It should:
// - accept raw arguments text snapshots
// - extract source from the tool input buffer
// - throttle refresh frequency
// - rely on WebView/HTML tolerance for invalid intermediate fragments
// - preserve the current successful preview until a new valid snapshot arrives
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart test/tools/handlers/create_artifact_tool_handler_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/chat_blocks/artifact_preview_surface.dart lib/tools/handlers/create_artifact_tool_handler.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/tools/handlers/create_artifact_tool_handler_test.dart
git commit -m "feat: progressive artifact rendering"
```

### Task 5: 更新 prompt 约束并做整体回归

**Files:**
- Modify: `lib/tools/handlers/create_artifact_tool_handler.dart`
- Test: `test/tools/handlers/create_artifact_tool_handler_test.dart`
- Test: `test/widgets/chat_blocks/artifact_block_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('create_artifact prompt emphasizes style-first and script-last ordering', () {
  final description = CreateArtifactToolHandler(...).definition.descriptionForModel;
  expect(description, contains('style'));
  expect(description, contains('script'));
  expect(description, contains('one screen'));
  expect(description, contains('two screens'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/tools/handlers/create_artifact_tool_handler_test.dart -r expanded`

Expected: fail until prompt copy is updated.

- [ ] **Step 3: 最小实现**

```dart
// Update English and Chinese prompt text to include stream-friendly guidance:
// - style first
// - visible content before script
// - script at the end
// - avoid blocking patterns
// - keep artifact concise when possible
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/tools/handlers/create_artifact_tool_handler_test.dart test/widgets/chat_blocks/artifact_block_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/tools/handlers/create_artifact_tool_handler.dart test/tools/handlers/create_artifact_tool_handler_test.dart test/widgets/chat_blocks/artifact_block_test.dart
git commit -m "feat: refine artifact streaming guidance"
```

### Self-Review

覆盖检查：
- runtime stream entry 模型：Task 1
- streaming LLM 上浮：Task 2
- projection/UI 消费：Task 3
- create_artifact 渐进渲染：Task 4
- prompt 约束与回归：Task 5

无 `TBD`、`TODO`、或与 spec 冲突的 TurnHarness 改造。
