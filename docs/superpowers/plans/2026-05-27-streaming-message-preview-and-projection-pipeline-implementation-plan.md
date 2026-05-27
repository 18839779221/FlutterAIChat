# Streaming Message Preview And Projection Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有扁平 runtime snapshot 方案迁移为统一 `StreamingMessageEvent` 预览事件管道，并用统一提交时序保证临时 preview 与正式消息的最终一致性。

**Architecture:** 保持 `TurnHarness -> ChatEvent` 主真相链路不变，把 provider streaming 适配层硬切到 `StreamingMessageEvent`，再通过统一提交管道串行分发给 `StreamingDecisionAccumulator` 与 `RuntimeStreamingPreviewProjector`。`ChatTimelineProjectionService` 继续作为唯一 UI 汇聚层，preview state 只作为 runtime-only read model 存在。  

**Tech Stack:** Flutter 3.35.7, Dart, `riverpod`, existing LLM runtime/adapters, existing chat timeline projection stack

---

### Task 1: 建立统一 preview 事件模型与 provider 风格 id 策略

**Files:**
- Create: `lib/models/llm/streaming_message_event.dart`
- Modify: `lib/models/llm/runtime/anthropic_stream_event_adapter.dart`
- Modify: `lib/models/llm/runtime/responses_stream_event_adapter.dart`
- Create: `lib/models/llm/runtime/chat_completions_stream_event_adapter.dart`
- Test: `test/models/llm/streaming_message_event_test.dart`
- Test: `test/models/llm/runtime/anthropic_stream_event_adapter_test.dart`
- Test: `test/models/llm/runtime/responses_stream_event_adapter_test.dart`
- Test: `test/models/llm/runtime/chat_completions_stream_event_adapter_test.dart`

- [ ] **Step 1: 为统一事件模型写失败测试**

```dart
test('streaming message events expose message and content block lifecycle', () {
  const event = StreamingContentBlockDeltaEvent(
    messageId: 'resp_1',
    contentBlockId: 'resp_1:text',
    deltaType: StreamingContentDeltaType.text,
    value: 'hel',
  );

  expect(event.messageId, 'resp_1');
  expect(event.contentBlockId, 'resp_1:text');
  expect(event.value, 'hel');
});
```

- [ ] **Step 2: 为 Anthropic adapter 写失败测试**

```dart
test('anthropic adapter preserves message start and block index lifecycle', () async {
  final events = await adapter.adapt(stream).toList();
  expect(events.first, isA<StreamingMessageStartEvent>());
  expect(events.whereType<StreamingContentBlockStartEvent>(), isNotEmpty);
});
```

- [ ] **Step 3: 为 Responses adapter 写失败测试**

```dart
test('responses adapter maps output text and function call deltas into block events', () async {
  final events = await adapter.adapt(stream).toList();
  expect(
    events.whereType<StreamingContentBlockDeltaEvent>().map((e) => e.deltaType),
    contains(StreamingContentDeltaType.inputJson),
  );
});
```

- [ ] **Step 4: 为 Chat Completions synthetic block 规则写失败测试**

```dart
test('chat completions adapter synthesizes text and tool blocks from deltas', () async {
  final events = await adapter.adapt(lines).toList();
  expect(events.whereType<StreamingMessageStartEvent>(), hasLength(1));
  expect(events.whereType<StreamingContentBlockStartEvent>(), isNotEmpty);
});
```

- [ ] **Step 5: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/streaming_message_event_test.dart test/models/llm/runtime/anthropic_stream_event_adapter_test.dart test/models/llm/runtime/responses_stream_event_adapter_test.dart test/models/llm/runtime/chat_completions_stream_event_adapter_test.dart`

Expected: FAIL because the unified preview event model and chat completions event adapter do not exist yet.

- [ ] **Step 6: 写最小实现**

实现：
- `StreamingMessageEvent` 抽象基类和五类具体事件
- `StreamingContentBlockType` / `StreamingContentDeltaType`
- Anthropic adapter 直接映射 message/block 生命周期
- Responses adapter 按 `response_id + item_id + content_index/summary_index` 生成 block id
- Chat Completions adapter 按 `message_id:text`、`message_id:thinking`、`message_id:tool:{index}` 合成 block

- [ ] **Step 7: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/streaming_message_event_test.dart test/models/llm/runtime/anthropic_stream_event_adapter_test.dart test/models/llm/runtime/responses_stream_event_adapter_test.dart test/models/llm/runtime/chat_completions_stream_event_adapter_test.dart`

Expected: PASS

- [ ] **Step 8: 提交这一小步**

```bash
git add lib/models/llm/streaming_message_event.dart lib/models/llm/runtime/anthropic_stream_event_adapter.dart lib/models/llm/runtime/responses_stream_event_adapter.dart lib/models/llm/runtime/chat_completions_stream_event_adapter.dart test/models/llm/streaming_message_event_test.dart test/models/llm/runtime/anthropic_stream_event_adapter_test.dart test/models/llm/runtime/responses_stream_event_adapter_test.dart test/models/llm/runtime/chat_completions_stream_event_adapter_test.dart
git commit -m "feat: add unified streaming message events"
```

### Task 2: 让 LLM streaming 主路径硬切到统一 preview 事件

**Files:**
- Modify: `lib/models/llm/runtime/openai_chat_completions_runtime.dart`
- Modify: `lib/models/llm/runtime/openai_responses_runtime.dart`
- Modify: `lib/models/llm/runtime/protocol_execution_runtime.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/streaming_planner_chunk.dart`
- Test: `test/models/llm/runtime/openai_chat_completions_runtime_test.dart`
- Test: `test/models/llm/runtime/openai_responses_runtime_test.dart`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 为 runtime streaming 出口改签名写失败测试**

```dart
test('protocol stream execution returns unified preview events', () async {
  final result = await runtime.streamExecute(...);
  expect(result.events, isA<Stream<StreamingMessageEvent>>());
});
```

- [ ] **Step 2: 为 ConfigurableHttpLLM 消费新事件流写失败测试**

```dart
test('configurable http llm consumes preview events without planner chunks', () async {
  final result = await llm.planTurnDecision(...);
  expect(result, isNotNull);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/runtime/openai_chat_completions_runtime_test.dart test/models/llm/runtime/openai_responses_runtime_test.dart test/models/llm/configurable_http_llm_test.dart`

Expected: FAIL because runtimes still expose planner chunks instead of unified preview events.

- [ ] **Step 4: 写最小实现**

实现：
- `ProtocolStreamExecutionResult` 以 `Stream<StreamingMessageEvent>` 为正式 streaming 出口
- `OpenAiChatCompletionsRuntime` 与 `OpenAiResponsesRuntime` 改为使用统一 event adapter
- `ConfigurableHttpLLM` 删除对旧 `StreamingPlannerChunk` 的主路径依赖
- 仅保留与非 streaming fallback 相关的必要兼容结构，不保留双轨 provider streaming 语义

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/runtime/openai_chat_completions_runtime_test.dart test/models/llm/runtime/openai_responses_runtime_test.dart test/models/llm/configurable_http_llm_test.dart`

Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/runtime/openai_chat_completions_runtime.dart lib/models/llm/runtime/openai_responses_runtime.dart lib/models/llm/runtime/protocol_execution_runtime.dart lib/models/llm/configurable_http_llm.dart lib/models/llm/streaming_planner_chunk.dart test/models/llm/runtime/openai_chat_completions_runtime_test.dart test/models/llm/runtime/openai_responses_runtime_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "refactor: route provider streaming through unified preview events"
```

### Task 3: 重写 StreamingDecisionAccumulator 为 ordered content block 累积器

**Files:**
- Modify: `lib/models/llm/streaming_decision_accumulator.dart`
- Modify: `lib/models/llm/adapters/sdk_responses_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart`
- Test: `test/models/llm/streaming_decision_accumulator_test.dart`
- Test: `test/models/llm/adapters/sdk_responses_adapter_test.dart`
- Test: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`

- [ ] **Step 1: 为 ordered content block snapshot 写失败测试**

```dart
test('accumulator preserves content block order across thinking text and tool use', () {
  final accumulator = StreamingDecisionAccumulator();
  accumulator.consume(const StreamingMessageStartEvent(messageId: 'm1'));
  accumulator.consume(const StreamingContentBlockStartEvent(
    messageId: 'm1',
    contentBlockId: 'm1:thinking',
    blockType: StreamingContentBlockType.thinking,
  ));
  accumulator.consume(const StreamingContentBlockDeltaEvent(
    messageId: 'm1',
    contentBlockId: 'm1:thinking',
    deltaType: StreamingContentDeltaType.thinking,
    value: 'plan',
  ));

  final snapshot = accumulator.currentSnapshot();
  expect(snapshot.blocks.single.type, StreamingContentBlockType.thinking);
});
```

- [ ] **Step 2: 为 final raw assistant message 回组写失败测试**

```dart
test('responses raw assistant message is assembled from ordered blocks', () {
  final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
  expect(raw?['output'], isNotEmpty);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/streaming_decision_accumulator_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`

Expected: FAIL because the accumulator still uses flat text/reasoning/tool draft buffers.

- [ ] **Step 4: 写最小实现**

实现：
- `StreamingDecisionAccumulator.consume(StreamingMessageEvent event)`
- message draft + ordered content block draft 内部模型
- `buildDecision()` 从 ordered blocks 提取 `assistantMessage` / `visibleReasoning` / `toolCalls`
- `currentSnapshot()` 输出新的 block snapshot 结构
- provider adapters 按 ordered blocks 回组 provider-shaped raw assistant message

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/streaming_decision_accumulator_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`

Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/streaming_decision_accumulator.dart lib/models/llm/adapters/sdk_responses_adapter.dart lib/models/llm/adapters/sdk_chat_completions_adapter.dart lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart test/models/llm/streaming_decision_accumulator_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart
git commit -m "refactor: accumulate streaming decision by content blocks"
```

### Task 4: 新建 runtime preview projector 与 preview state provider

**Files:**
- Create: `lib/models/chat/runtime_streaming_preview_state.dart`
- Create: `lib/services/runtime_streaming_preview_projector.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/models/chat/runtime_stream_entry.dart`
- Test: `test/services/runtime_streaming_preview_projector_test.dart`
- Test: `test/providers/chat_ui_providers_test.dart`

- [ ] **Step 1: 为 preview projector 写失败测试**

```dart
test('preview projector folds block deltas into runtime preview message state', () {
  final projector = RuntimeStreamingPreviewProjector();
  projector.consume(const StreamingMessageStartEvent(messageId: 'm1'));
  projector.consume(const StreamingContentBlockStartEvent(
    messageId: 'm1',
    contentBlockId: 'm1:text',
    blockType: StreamingContentBlockType.text,
  ));
  projector.consume(const StreamingContentBlockDeltaEvent(
    messageId: 'm1',
    contentBlockId: 'm1:text',
    deltaType: StreamingContentDeltaType.text,
    value: 'hello',
  ));

  expect(projector.currentState().messages.single.blocks.single.text, 'hello');
});
```

- [ ] **Step 2: 为 preview state provider 替代旧 runtime stream entries 写失败测试**

```dart
test('timeline projection provider reads runtime preview state', () {
  // Build a provider container and assert the projection receives preview state.
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/services/runtime_streaming_preview_projector_test.dart test/providers/chat_ui_providers_test.dart`

Expected: FAIL because runtime preview state/projector do not exist.

- [ ] **Step 4: 写最小实现**

实现：
- runtime-only `RuntimeStreamingPreviewState`
- `RuntimeStreamingPreviewProjector.consume(...)`
- `runtimeStreamingPreviewStateProvider`
- 保留 `runtimeAssistantDraftProvider` 现有职责，只替换旧的 `runtimeStreamEntriesProvider` 主语义

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/services/runtime_streaming_preview_projector_test.dart test/providers/chat_ui_providers_test.dart`

Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/chat/runtime_streaming_preview_state.dart lib/services/runtime_streaming_preview_projector.dart lib/providers/chat_ui_providers.dart lib/models/chat/runtime_stream_entry.dart test/services/runtime_streaming_preview_projector_test.dart test/providers/chat_ui_providers_test.dart
git commit -m "feat: add runtime streaming preview projector"
```

### Task 5: 建立统一消费与提交管道，收敛 preview/final 替换时序

**Files:**
- Create: `lib/services/turn_projection_dispatcher.dart`
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Test: `test/services/turn_projection_dispatcher_test.dart`
- Test: `test/controllers/agent_event_processor_test.dart`

- [ ] **Step 1: 为统一提交管道的 final replace 语义写失败测试**

```dart
test('dispatcher clears preview before appending final answer for the same message', () async {
  // Feed streaming events for message m1, then feed finalAnswer truth event,
  // and assert preview is cleared before the completed assistant message appears.
});
```

- [ ] **Step 2: 为 finalized message 拒绝晚到 delta 写失败测试**

```dart
test('dispatcher drops late preview events for finalized message', () async {
  // Finalize m1, then feed another preview delta for m1.
  // Assert the preview state remains unchanged.
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/services/turn_projection_dispatcher_test.dart test/controllers/agent_event_processor_test.dart`

Expected: FAIL because preview and truth still commit state through separate paths.

- [ ] **Step 4: 写最小实现**

实现：
- 统一提交接口，允许 `StreamingMessageEvent` 与 `ChatEvent` 共享同一消费管道
- 串行提交 preview / truth 事件
- message 生命周期状态：`streaming` / `finalizing` / `finalized`
- `finalAnswer` 提交时先清 preview，再提交正式消息
- finalized 后丢弃同 message 的晚到 preview 事件并记录日志

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/services/turn_projection_dispatcher_test.dart test/controllers/agent_event_processor_test.dart`

Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/services/turn_projection_dispatcher.dart lib/controllers/agent_event_processor.dart lib/models/chat_event.dart lib/controllers/chat_send_coordinator.dart test/services/turn_projection_dispatcher_test.dart test/controllers/agent_event_processor_test.dart
git commit -m "feat: add unified projection dispatch pipeline"
```

### Task 6: 让 ChatTimelineProjectionService 消费 preview state，并替换旧 snapshot path

**Files:**
- Modify: `lib/services/chat_timeline_projection_service.dart`
- Modify: `lib/models/chat/chat_timeline_projection.dart`
- Modify: `lib/models/chat/runtime_assistant_draft.dart`
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Test: `test/services/chat_timeline_projection_service_test.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

- [ ] **Step 1: 为 timeline projection 消费 preview state 写失败测试**

```dart
test('timeline projection merges runtime preview message blocks with persisted truth blocks', () {
  // Build projection with persisted messages plus runtime preview state.
  // Assert the projection contains runtime blocks before final truth arrives.
});
```

- [ ] **Step 2: 为 artifact runtime preview 从 tool_use block 读取参数累积写失败测试**

```dart
test('artifact preview reads runtime tool_use block from preview state', () {
  // Assert create_artifact preview uses the unified preview state rather than legacy runtime entries.
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/services/chat_timeline_projection_service_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

Expected: FAIL because projection still depends on legacy runtime snapshot entries.

- [ ] **Step 4: 写最小实现**

实现：
- `ChatTimelineProjectionService` 改为消费 runtime preview state
- 同时保留正式 truth blocks 与 runtime preview blocks 的统一 merge
- artifact renderer 从 `tool_use(create_artifact)` block 读取参数累积
- 删除旧 `runtimeSnapshots -> runtimeStreamEntries` 的主路径依赖

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/services/chat_timeline_projection_service_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/services/chat_timeline_projection_service.dart lib/models/chat/chat_timeline_projection.dart lib/models/chat/runtime_assistant_draft.dart lib/widgets/chat_blocks/artifact_preview_surface.dart test/services/chat_timeline_projection_service_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart
git commit -m "refactor: project runtime preview state into timeline"
```

### Task 7: 删除旧双轨结构并做回归

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/streaming_planner_chunk.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `test/models/llm/configurable_http_llm_test.dart`
- Test: `test/services/chat_timeline_projection_service_test.dart`
- Test: `test/widgets/chat_blocks/artifact_block_test.dart`
- Test: `test/pages/artifact_detail_page_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_responses_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 写失败测试，确认旧 runtime snapshot 入口已不再被依赖**

```dart
test('streaming pipeline no longer requires legacy runtime snapshots', () async {
  // Assert the new flow reaches preview + final truth without runtimeSnapshots().
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart test/services/chat_timeline_projection_service_test.dart test/widgets/chat_blocks/artifact_block_test.dart test/pages/artifact_detail_page_test.dart`

Expected: FAIL until the legacy snapshot-based flow is removed.

- [ ] **Step 3: 写最小实现**

实现：
- 删除旧 `StreamingPlannerChunk` 主链路语义与遗留调用
- 清理 `runtimeStreamEntriesProvider` 的剩余主路径依赖
- 更新 `README.md` / `AGENTS.md` 中对 streaming preview 架构的描述
- 保持主链路 `TurnHarness` 与 transcript truth 文义不变

- [ ] **Step 4: 运行本地回归测试**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart test/models/llm/streaming_decision_accumulator_test.dart test/services/chat_timeline_projection_service_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/widgets/chat_blocks/artifact_block_test.dart test/pages/artifact_detail_page_test.dart`

Expected: PASS

- [ ] **Step 5: 运行 live provider 回归**

Run:
- `bash scripts/run_live_llm_contract_tests.sh minimax-openai`
- `bash scripts/run_live_llm_contract_tests.sh minimax-openai minimax-anthropic`
- `HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS=minimax-openai fvm flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
- `HEADLESS_LIVE_PROVIDER_RESPONSES=minimax-openai fvm flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_responses_test.dart`
- `HEADLESS_LIVE_PROVIDER_ANTHROPIC=minimax-anthropic fvm flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

Expected: PASS for touched API styles and append-only transcript tool round-trip flows.

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/configurable_http_llm.dart lib/models/llm/streaming_planner_chunk.dart lib/providers/chat_ui_providers.dart README.md AGENTS.md test/models/llm/configurable_http_llm_test.dart test/services/chat_timeline_projection_service_test.dart test/widgets/chat_blocks/artifact_block_test.dart test/pages/artifact_detail_page_test.dart test/integration/chat_send_live/chat_send_live_chat_completions_test.dart test/integration/chat_send_live/chat_send_live_responses_test.dart test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "refactor: converge preview streaming pipeline"
```
