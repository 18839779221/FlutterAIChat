# Runtime Preview 接管整体流式渲染 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `runtimeStreamingPreviewState` 接管整体运行中 assistant 回复显示，使正文、thinking、tool_use、artifact 都通过统一 projection 进入 timeline，并由 `finalAnswer` 只负责最终 takeover。

**Architecture:** 保持 `TurnHarness -> ChatEvent` 主真相链路不变，把运行中 UI 显示的主状态收敛到 `runtime preview`。`ChatTimelineProjectionService` 新增通用 preview block 投影层，`ChatTimelineRow` 继续只消费统一 projection，`TurnProjectionDispatcher` 继续负责 preview/final 串行仲裁。  

**Tech Stack:** Flutter 3.35.7, Dart, Riverpod, existing streaming preview pipeline, existing chat timeline projection stack

---

## 文件结构与职责

### 需要重点修改的文件

- `lib/services/chat_timeline_projection_service.dart`
  - 增加通用 preview block -> `AssistantTurnBlock` 投影
  - 统一 merge preview block、truth block、runtime draft block
- `lib/models/chat/chat_timeline_projection.dart`
  - 如有必要补充 projection 元数据，标识运行中 preview block 的来源与可见状态
- `lib/widgets/chat_timeline/chat_timeline_row.dart`
  - 让运行中正文 / thinking / tool workflow 都从统一 projection 正常渲染
- `lib/widgets/chat_message_list.dart`
  - 保持只消费统一 projection；必要时调整 stable key / last-item streaming 判断
- `lib/controllers/agent_event_processor.dart`
  - 弱化普通正文对 generating message 的依赖
  - 缩窄 `runtimeAssistantDraftProvider` 的职责
- `lib/providers/chat_ui_providers.dart`
  - 继续以 `runtimeStreamingPreviewStateProvider` 作为运行中主入口
- `lib/widgets/debug/debug_turn_inspector_sheet.dart`
  - 暴露新的运行中 block 观测信息

### 需要重点验证的测试文件

- `test/services/chat_timeline_projection_service_test.dart`
- `test/widgets/chat_message_list_test.dart`
- `test/widgets/chat_blocks/chat_blocks_test.dart`
- `test/controllers/chat_send_coordinator_test.dart`
- `test/controllers/chat_controller_test.dart`
- `test/controllers/chat_send_coordinator_test.dart`
- `test/providers/chat_ui_providers_test.dart`
- `test/services/turn_projection_dispatcher_test.dart`
- `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
- `test/integration/chat_send_live/chat_send_live_responses_test.dart`
- `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

---

### Task 1: 让通用 preview block 进入 timeline projection

**Files:**
- Modify: `lib/services/chat_timeline_projection_service.dart`
- Modify: `lib/models/chat/chat_timeline_projection.dart`
- Modify: `lib/models/chat/assistant_turn_block.dart`
- Test: `test/services/chat_timeline_projection_service_test.dart`

- [ ] **Step 1: 为 text / thinking / tool_use 的通用 preview 投影写失败测试**

```dart
test('projection maps runtime preview text block into finalResponse block', () {
  final projection = service.build(
    messages: const [],
    runtimePreviewState: RuntimeStreamingPreviewState(
      messages: [
        RuntimeStreamingPreviewMessage(
          messageId: 'm1',
          blocks: [
            RuntimeStreamingPreviewBlock(
              contentBlockId: 'm1:text',
              blockType: StreamingContentBlockType.text,
              text: 'hello',
            ),
          ],
        ),
      ],
    ),
  );

  expect(
    projection.assistantBlocks.any(
      (block) =>
          block.type == AssistantTurnBlockType.finalResponse &&
          block.text == 'hello',
    ),
    isTrue,
  );
});
```

- [ ] **Step 2: 为 thinking preview 投影写失败测试**

```dart
test('projection maps runtime preview thinking block into analysis block', () {
  // Assert thinking block becomes a runtime analysis block.
});
```

- [ ] **Step 3: 为普通 tool_use preview 投影写失败测试**

```dart
test('projection maps runtime preview tool_use block into tool workflow block', () {
  // Assert non-artifact tool_use block becomes a runtime toolWorkflow block.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/chat_timeline_projection_service_test.dart`

Expected: FAIL because runtime preview currently only becomes artifact-oriented blocks.

- [ ] **Step 5: 写最小实现**

实现：
- 在 `ChatTimelineProjectionService` 中新增通用 preview block projector
- `text` block -> runtime `finalResponse`
- `thinking` block -> runtime `analysis`
- `tool_use` block -> runtime `toolWorkflow`
- 保留 `tool_use(create_artifact)` -> runtime `artifact`
- 如有必要，为 `AssistantTurnBlock.payload` 增加极轻量的 runtime preview 来源标记

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/chat_timeline_projection_service_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/services/chat_timeline_projection_service.dart lib/models/chat/chat_timeline_projection.dart lib/models/chat/assistant_turn_block.dart test/services/chat_timeline_projection_service_test.dart
git commit -m "feat: project runtime preview blocks into timeline"
```

### Task 2: 让 timeline widget 真正消费运行中 preview 正文与 thinking

**Files:**
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_blocks/streaming_response_block.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 为 preview 驱动的运行中正文显示写失败测试**

```dart
testWidgets('chat message list renders streaming response from runtime preview without generating source message', (tester) async {
  // Build projection with runtime preview finalResponse block only.
  // Assert StreamingResponseBlock is visible.
});
```

- [ ] **Step 2: 为 preview 驱动的 thinking 显示写失败测试**

```dart
testWidgets('chat timeline row renders runtime analysis block from preview state', (tester) async {
  // Assert runtime analysis block is visible without persisted assistant message.
});
```

- [ ] **Step 3: 为 finalResponse runtime preview 的 stable key / repaint 写失败测试**

```dart
testWidgets('preview-driven final response updates in place across growing text', (tester) async {
  // Pump with hello, then hello world, and assert one stable row updates in place.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart`

Expected: FAIL because current widget path still assumes generating source message for streaming正文。

- [ ] **Step 5: 写最小实现**

实现：
- `ChatTimelineRow` 对 runtime preview 生成的 `finalResponse` block 也使用 `StreamingResponseBlock`
- 不再仅通过 `sourceMessage.status == generating` 判断运行中正文
- 保持 tool/workflow/result/artifact 仍只来自统一 projection
- 调整 `ChatMessageList` 中与 streaming last-row 相关的 key / identity 逻辑，保证 preview 增长时同一 row 原地更新

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/widgets/chat_timeline/chat_timeline_row.dart lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/streaming_response_block.dart test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "feat: render runtime preview blocks in chat timeline"
```

### Task 3: 收敛 AgentEventProcessor 对普通正文 generating message 的依赖

**Files:**
- Modify: `lib/controllers/agent_event_processor.dart`
- Modify: `lib/services/assistant_stream_output_buffer.dart`
- Modify: `lib/models/chat/runtime_assistant_draft.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: 为普通正文不再依赖 generating message 写失败测试**

```dart
test('final answer path can stream through runtime preview without creating a persisted generating assistant message', () async {
  // Feed preview events, then final answer, and assert no duplicate generating message remains.
});
```

- [ ] **Step 2: 为 runtimeAssistantDraftProvider 职责缩窄写失败测试**

```dart
test('reasoning draft does not duplicate preview-driven text block display', () async {
  // Assert preview text and runtime draft are not both used for the same visible response.
});
```

- [ ] **Step 3: 为 final takeover 后清理临时正文状态写失败测试**

```dart
test('final answer clears temporary runtime response state after takeover', () async {
  // Assert runtime preview and runtime draft are cleared after final truth lands.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart`

Expected: FAIL because current processor still treats `assistantTextDelta` + generating message as正文 streaming主路径。

- [ ] **Step 5: 写最小实现**

实现：
- 缩窄 `AgentEventProcessor._onAssistantTextDelta(...)` 的正文主职责
- 仅在仍有 truth-side 必要场景时保留最小兼容
- 避免 preview-driven 正文显示与 generating message 并行出现
- 缩窄 `runtimeAssistantDraftProvider` 到非通用正文 streaming 场景
- 视需要简化 `AssistantStreamOutputBuffer` 在普通正文链上的使用范围

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/controllers/agent_event_processor.dart lib/services/assistant_stream_output_buffer.dart lib/models/chat/runtime_assistant_draft.dart test/controllers/chat_send_coordinator_test.dart test/controllers/chat_controller_test.dart
git commit -m "refactor: narrow truth-side streaming response path"
```

### Task 4: 强化 preview / final takeover 与运行时观测

**Files:**
- Modify: `lib/services/turn_projection_dispatcher.dart`
- Modify: `lib/widgets/debug/debug_turn_inspector_sheet.dart`
- Modify: `lib/services/debug/debug_turn_inspector_projection_service.dart`
- Test: `test/services/turn_projection_dispatcher_test.dart`
- Test: `test/widgets/debug/debug_turn_inspector_sheet_test.dart`

- [ ] **Step 1: 为 preview-driven 正文的 final takeover 写失败测试**

```dart
test('dispatcher final takeover removes preview-driven response block before completed truth appears', () async {
  // Assert no duplicate runtime preview response remains after final answer.
});
```

- [ ] **Step 2: 为晚到 delta 拒绝逻辑补失败测试**

```dart
test('dispatcher drops late preview delta after final takeover for response block', () async {
  // Finalize message, then send another text delta, and assert UI state stays finalized.
});
```

- [ ] **Step 3: 为 debug inspector 暴露运行中 block 观测写失败测试**

```dart
testWidgets('debug inspector shows runtime preview message and block counts for streaming response', (tester) async {
  // Assert inspector exposes preview message/block summary for response streaming.
});
```

- [ ] **Step 4: 运行测试确认失败**

Run: `flutter test test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

Expected: FAIL because current observability is still artifact/tooling oriented and takeover assertions do not cover preview-driven正文。

- [ ] **Step 5: 写最小实现**

实现：
- 保持 `TurnProjectionDispatcher` 作为唯一串行仲裁点
- 补齐 preview-driven 正文 takeover 的断言与日志
- 在 debug inspector 中加入运行中 preview message / block / type 摘要
- 让一次真实 streaming 回复能被直接判断卡在哪一层

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

Expected: PASS

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/services/turn_projection_dispatcher.dart lib/widgets/debug/debug_turn_inspector_sheet.dart lib/services/debug/debug_turn_inspector_projection_service.dart test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart
git commit -m "feat: observe preview-driven streaming takeover"
```

### Task 5: 回归 artifact / tool_use 路径并验证三种 API style

**Files:**
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_responses_test.dart`
- Test: `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

- [ ] **Step 1: 为 artifact 与通用 preview 共存写失败测试**

```dart
testWidgets('artifact runtime preview still renders while generic preview response blocks are enabled', (tester) async {
  // Assert artifact preview and generic runtime response projection do not conflict.
});
```

- [ ] **Step 2: 为 live-headless 场景补验证点**

```dart
testWidgets('live streaming scenario exposes preview-driven response before final answer completes', (tester) async {
  // Assert at least one runtime preview response block is visible before final truth lands.
});
```

- [ ] **Step 3: 运行本地测试确认失败**

Run: `flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart`

Expected: FAIL until generic preview rendering and artifact preview coexist cleanly.

- [ ] **Step 4: 写最小实现**

实现：
- 确认 artifact renderer 继续作为通用 `tool_use(create_artifact)` preview 的专用消费方
- 更新 `README.md` / `AGENTS.md` 中对 streaming rendering 主路径的描述
- 在 live integration 断言中加入“运行中 preview 已经可见”的验证，不只验证最终 `ModelTurnDecision`

- [ ] **Step 5: 运行本地回归测试**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

If active `flutter` is not `3.35.7`, run: `fvm flutter test test/services/chat_timeline_projection_service_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/services/turn_projection_dispatcher_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart`

Expected: PASS

- [ ] **Step 6: 运行 live provider 回归**

Run:
- `bash scripts/run_live_llm_contract_tests.sh minimax-openai`
- `bash scripts/run_live_llm_contract_tests.sh minimax-openai minimax-anthropic`
- `HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS=minimax-openai flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_chat_completions_test.dart`
- `HEADLESS_LIVE_PROVIDER_RESPONSES=minimax-openai flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_responses_test.dart`
- `HEADLESS_LIVE_PROVIDER_ANTHROPIC=minimax-anthropic flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

If active `flutter` is not `3.35.7`, prefix the `flutter test` commands with `fvm`.

Expected: PASS for touched API styles, including one assertion that runtime preview block appears before final truth takeover.

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/widgets/chat_blocks/artifact_preview_surface.dart README.md AGENTS.md test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_preview_surface_debouncing_test.dart test/integration/chat_send_live/chat_send_live_chat_completions_test.dart test/integration/chat_send_live/chat_send_live_responses_test.dart test/integration/chat_send_live/chat_send_live_anthropic_test.dart
git commit -m "refactor: complete preview-driven streaming rendering"
```

---

## 执行注意事项

- 不要在同一任务里同时重写 projection、widget、processor 三层；按任务顺序逐层收敛，避免双轨状态定位失真。
- 每一步都先写失败测试，再做最小实现，不要直接并行清理所有旧逻辑。
- `assistantTextDelta` 不要一次性删除到完全不可用；在 Task 3 之前只允许把它从“正文主路径”降级，不要破坏现有 truth 语义。
- `runtimeAssistantDraftProvider` 的职责缩窄要谨慎，优先保护 ask-user / 特殊 reasoning 场景。
- 所有新增 spec / plan / 文档内容必须保持中文。
- live provider 回归是本计划的完成门槛之一，不能只靠 mocked test 宣布完成。
