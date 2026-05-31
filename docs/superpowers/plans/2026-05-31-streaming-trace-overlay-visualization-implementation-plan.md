# Streaming Trace Overlay Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在聊天页中为运行中状态条补一套默认隐藏、长按唤起、再次长按关闭的轻量流式时间线浮层，帮助现场判断 provider、preview、projection、UI 可见和 final takeover 的真实时序。

**Architecture:** 本实现保持现有 `provider/runtime -> preview state -> timeline projection -> widget` 主链路不变，只新增一条 runtime-only 的 `StreamingTraceSnapshot` 读模型与对应采集节点。聊天页 UI 通过页面级 overlay coordinator 消费这份 trace projection，入口只挂在 `LatestMessageRunningStatusTail`，不新增设置开关与常驻调试按钮。

**Tech Stack:** Flutter 3.35.7、Dart、Riverpod、现有 `Logger` / `ChatTraceRecorder` / `RuntimeStreamingPreviewState` / `ChatTimelineProjectionService` / `ChatPage`

---

## File Structure

### New files

- `lib/models/debug/streaming_trace_snapshot.dart`
  - 定义流式时间线浮层消费的只读模型：snapshot、entry、stage、status
- `lib/services/debug/streaming_trace_recorder.dart`
  - 负责按 `traceId` 聚合关键节点，维护当前活跃 snapshot
- `lib/widgets/debug/streaming_trace_overlay_card.dart`
  - 负责渲染轻量浮层卡片：顶部摘要 + 下方简版时间线

### Modified files

- `lib/providers/chat_ui_providers.dart`
  - 新增 streaming trace provider、overlay 可见性 provider、状态条长按 toggle 协调入口
- `lib/models/llm/configurable_http_llm.dart`
  - 在统一 streaming event 消费边界记录 `stream.event_received`
- `lib/services/runtime_streaming_preview_projector.dart`
  - 记录 `preview.event_consumed`
- `lib/providers/chat_ui_providers.dart`
  - `RuntimeStreamingPreviewController._publishState` 记录 `preview.state_committed`
- `lib/services/chat_timeline_projection_service.dart`
  - 记录 `timeline_projection_built`
- `lib/services/turn_projection_dispatcher.dart`
  - 记录 `final.takeover`，并在 turn 完成/清空 preview 时同步更新 active trace 生命周期
- `lib/widgets/chat_blocks/streaming_response_block.dart`
  - 记录 `ui.first_visible` / `ui.updated`
- `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
  - 增加长按回调能力，但不内嵌 overlay 业务
- `lib/widgets/chat_timeline/chat_timeline_row.dart`
  - 把状态条长按意图与当前锚点信息向上挂接
- `lib/widgets/chat_message_list.dart`
  - 继续在 timeline row 组装 running tail，并把长按 toggle 入口接到页面级 coordinator
- `lib/pages/chat_page.dart`
  - 添加页面级 overlay 宿主，不改消息列表布局
- `README.md`
  - 记录新的流式时间线调试入口与架构边界
- `AGENTS.md`
  - 记录该可视化属于 runtime-only observability，不进入 transcript truth

### Test files

- `test/services/debug/streaming_trace_recorder_test.dart`
- `test/services/chat_timeline_projection_service_test.dart`
- `test/widgets/chat_blocks/latest_message_running_status_tail_test.dart`
- `test/widgets/debug/streaming_trace_overlay_card_test.dart`
- `test/widgets/chat_message_list_test.dart`
- `test/pages/chat_page_test.dart`

## Task 1: Add Streaming Trace Read Model and Recorder

**Files:**
- Create: `lib/models/debug/streaming_trace_snapshot.dart`
- Create: `lib/services/debug/streaming_trace_recorder.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Test: `test/services/debug/streaming_trace_recorder_test.dart`

- [ ] **Step 1: Write the failing recorder tests**

```dart
test('records ordered streaming stages into one active snapshot', () {
  final recorder = StreamingTraceRecorder();

  recorder.recordStage(
    traceId: 'trace_1',
    turnId: 'turn_1',
    stage: StreamingTraceStage.streamEventReceived,
    details: {'blockType': 'text'},
    timestamp: DateTime(2026, 5, 31, 10, 0, 0),
  );
  recorder.recordStage(
    traceId: 'trace_1',
    turnId: 'turn_1',
    stage: StreamingTraceStage.previewStateCommitted,
    details: {'textLength': 12},
    timestamp: DateTime(2026, 5, 31, 10, 0, 0, 0, 50),
  );

  final snapshot = recorder.activeSnapshot;
  expect(snapshot?.traceId, 'trace_1');
  expect(snapshot?.entries.length, 2);
  expect(snapshot?.currentStage, StreamingTraceStage.previewStateCommitted);
  expect(snapshot?.entries.last.elapsedMsFromStart, 50);
});

test('toggleOverlay only opens for matching active anchor and closes on same anchor', () {
  final coordinator = StreamingTraceOverlayCoordinator();
  coordinator.toggle(anchorId: 'tail_1', hasActiveTrace: true);
  expect(coordinator.isVisible, isTrue);
  coordinator.toggle(anchorId: 'tail_1', hasActiveTrace: true);
  expect(coordinator.isVisible, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/debug/streaming_trace_recorder_test.dart`

Expected: FAIL with missing `StreamingTraceRecorder` / `StreamingTraceSnapshot` / overlay coordinator symbols.

- [ ] **Step 3: Add minimal snapshot / entry / stage model**

```dart
enum StreamingTraceStage {
  streamEventReceived,
  previewEventConsumed,
  previewStateCommitted,
  timelineProjectionBuilt,
  uiFirstVisible,
  uiUpdated,
  finalTakeover,
}

enum StreamingTraceLifecycleStatus { idle, running, completed, aborted }

class StreamingTraceEntry {
  const StreamingTraceEntry({
    required this.eventId,
    required this.traceId,
    required this.stage,
    required this.timestamp,
    required this.elapsedMsFromStart,
    required this.title,
    this.details = const <String, dynamic>{},
  });
}

class StreamingTraceSnapshot {
  const StreamingTraceSnapshot({
    required this.traceId,
    required this.turnId,
    required this.status,
    required this.currentStage,
    required this.summaryText,
    required this.startedAt,
    this.firstVisibleAt,
    this.takeoverAt,
    this.entries = const <StreamingTraceEntry>[],
  });
}
```

- [ ] **Step 4: Implement recorder and lightweight overlay coordinator**

```dart
class StreamingTraceRecorder {
  StreamingTraceSnapshot? _activeSnapshot;

  StreamingTraceSnapshot? get activeSnapshot => _activeSnapshot;

  void recordStage({
    required String traceId,
    required String turnId,
    required StreamingTraceStage stage,
    required DateTime timestamp,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) { ... }

  void markCompleted({required String traceId, DateTime? takeoverAt}) { ... }
  void clear() { ... }
}

class StreamingTraceOverlayCoordinator extends StateNotifier<StreamingTraceOverlayState> {
  void toggle({
    required String anchorId,
    required bool hasActiveTrace,
  }) { ... }

  void closeIfAnchorDisappeared() { ... }
}
```

- [ ] **Step 5: Wire providers for active snapshot and overlay state**

```dart
final streamingTraceRecorderProvider = Provider<StreamingTraceRecorder>((ref) {
  return StreamingTraceRecorder();
});

final streamingTraceSnapshotProvider =
    StateProvider<StreamingTraceSnapshot?>((ref) => null);

final streamingTraceOverlayCoordinatorProvider = StateNotifierProvider<
    StreamingTraceOverlayCoordinator, StreamingTraceOverlayState>((ref) {
  return StreamingTraceOverlayCoordinator();
});
```

- [ ] **Step 6: Run tests to verify recorder behavior passes**

Run: `flutter test test/services/debug/streaming_trace_recorder_test.dart`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/models/debug/streaming_trace_snapshot.dart \
  lib/services/debug/streaming_trace_recorder.dart \
  lib/providers/chat_ui_providers.dart \
  test/services/debug/streaming_trace_recorder_test.dart
git commit -m "feat: add streaming trace recorder"
```

## Task 2: Instrument Provider, Preview, Projection, and Takeover Stages

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/services/runtime_streaming_preview_projector.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/services/chat_timeline_projection_service.dart`
- Modify: `lib/services/turn_projection_dispatcher.dart`
- Test: `test/services/chat_timeline_projection_service_test.dart`
- Test: `test/services/debug/streaming_trace_recorder_test.dart`

- [ ] **Step 1: Write failing stage instrumentation tests**

```dart
test('projection build records timelineProjectionBuilt with merged counts', () {
  final recorder = StreamingTraceRecorder();
  final service = ChatTimelineProjectionService(
    streamingTraceRecorder: recorder,
  );

  service.build(
    groupId: 1,
    messages: [...],
    runtimePreviewState: previewStateWithText('hello'),
  );

  final snapshot = recorder.activeSnapshot!;
  expect(
    snapshot.entries.any((e) => e.stage == StreamingTraceStage.timelineProjectionBuilt),
    isTrue,
  );
});

test('final takeover marks active trace completed', () async {
  final recorder = StreamingTraceRecorder();
  final dispatcher = buildDispatcher(recorder: recorder);

  recorder.recordStage(
    traceId: 'trace_1',
    turnId: 'turn_1',
    stage: StreamingTraceStage.streamEventReceived,
    timestamp: DateTime(2026, 5, 31, 10, 0, 0),
  );

  await dispatcher.dispatchTruthEvent(finalAnswerEvent, (_) async {});

  expect(recorder.activeSnapshot?.status, StreamingTraceLifecycleStatus.completed);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart test/services/debug/streaming_trace_recorder_test.dart`

Expected: FAIL because the recorder is not yet injected into projection/dispatch paths.

- [ ] **Step 3: Record `stream.event_received` near the unified streaming event consumption boundary**

```dart
await _consumeStreamingEvents(
  events: events,
  accumulator: accumulator,
  onEvent: (event) {
    streamingTraceRecorder?.recordStage(
      traceId: _traceIdFor(event),
      turnId: turnId,
      stage: StreamingTraceStage.streamEventReceived,
      timestamp: DateTime.now(),
      details: {
        'messageId': event.messageId,
        'eventType': event.runtimeType.toString(),
      },
    );
  },
);
```

- [ ] **Step 4: Record `preview.event_consumed` and `preview.state_committed`**

```dart
// RuntimeStreamingPreviewProjector.consume(...)
streamingTraceRecorder?.recordStage(
  traceId: traceId,
  turnId: turnId,
  stage: StreamingTraceStage.previewEventConsumed,
  timestamp: timestamp,
  details: {'deltaType': event.deltaType.name},
);

// RuntimeStreamingPreviewController._publishState(...)
streamingTraceRecorder?.recordStage(
  traceId: activeTraceId,
  turnId: activeTurnId,
  stage: StreamingTraceStage.previewStateCommitted,
  timestamp: now,
  details: {'messageCount': nextState.messages.length},
);
```

- [ ] **Step 5: Record `timeline_projection_built` and `final.takeover`**

```dart
streamingTraceRecorder?.recordStage(
  traceId: traceId,
  turnId: resolvedTurnId,
  stage: StreamingTraceStage.timelineProjectionBuilt,
  timestamp: DateTime.now(),
  details: {
    'assistantBlockCount': mergedBlocks.length,
    'runtimePreviewBlockCount': runtimePreviewBlocks.length,
  },
);

streamingTraceRecorder?.recordStage(
  traceId: traceId,
  turnId: traceTurnId,
  stage: StreamingTraceStage.finalTakeover,
  timestamp: DateTime.now(),
);
streamingTraceRecorder?.markCompleted(traceId: traceId, takeoverAt: DateTime.now());
```

- [ ] **Step 6: Run focused tests to verify instrumentation passes**

Run: `flutter test test/services/chat_timeline_projection_service_test.dart test/services/debug/streaming_trace_recorder_test.dart`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/models/llm/configurable_http_llm.dart \
  lib/services/runtime_streaming_preview_projector.dart \
  lib/providers/chat_ui_providers.dart \
  lib/services/chat_timeline_projection_service.dart \
  lib/services/turn_projection_dispatcher.dart \
  test/services/chat_timeline_projection_service_test.dart \
  test/services/debug/streaming_trace_recorder_test.dart
git commit -m "feat: instrument streaming trace stages"
```

## Task 3: Add UI Visibility Instrumentation and Overlay Card

**Files:**
- Modify: `lib/widgets/chat_blocks/streaming_response_block.dart`
- Create: `lib/widgets/debug/streaming_trace_overlay_card.dart`
- Modify: `lib/pages/chat_page.dart`
- Test: `test/widgets/debug/streaming_trace_overlay_card_test.dart`
- Test: `test/pages/chat_page_test.dart`

- [ ] **Step 1: Write failing UI visibility and overlay rendering tests**

```dart
testWidgets('streaming response records first visible only once', (tester) async {
  final recorder = StreamingTraceRecorder();

  await tester.pumpWidget(buildStreamingBlock(
    recorder: recorder,
    text: 'hello',
    traceId: 'trace_1',
  ));

  final snapshot = recorder.activeSnapshot!;
  expect(
    snapshot.entries.where((e) => e.stage == StreamingTraceStage.uiFirstVisible),
    hasLength(1),
  );
});

testWidgets('overlay card renders summary and ordered entries', (tester) async {
  await tester.pumpWidget(buildOverlayCard(
    snapshot: sampleStreamingTraceSnapshot(),
  ));

  expect(find.text('当前卡在 preview -> projection'), findsOneWidget);
  expect(find.textContaining('ui.first_visible'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/debug/streaming_trace_overlay_card_test.dart test/pages/chat_page_test.dart`

Expected: FAIL because the overlay card and visibility instrumentation do not exist yet.

- [ ] **Step 3: Instrument `StreamingResponseBlock` for `ui.first_visible` and `ui.updated`**

```dart
if (!_hasRecordedFirstVisible && text.trim().isNotEmpty) {
  recorder.recordStage(
    traceId: traceId,
    turnId: turnId,
    stage: StreamingTraceStage.uiFirstVisible,
    timestamp: DateTime.now(),
    details: {'visibleTextLength': text.length},
  );
  _hasRecordedFirstVisible = true;
} else if (text.length != _lastVisibleLength) {
  recorder.recordStage(
    traceId: traceId,
    turnId: turnId,
    stage: StreamingTraceStage.uiUpdated,
    timestamp: DateTime.now(),
    details: {'visibleTextLength': text.length},
  );
}
```

- [ ] **Step 4: Build the lightweight overlay card**

```dart
class StreamingTraceOverlayCard extends StatelessWidget {
  const StreamingTraceOverlayCard({
    super.key,
    required this.snapshot,
  });

  final StreamingTraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryHeader(snapshot: snapshot),
        _EntryList(entries: snapshot.entries),
      ],
    );
  }
}
```

- [ ] **Step 5: Mount the overlay in `ChatPage` without changing message list layout**

```dart
if (overlayState.isVisible && snapshot != null)
  Positioned(
    left: spacing.lg,
    right: spacing.lg,
    bottom: pendingConfirmation == null ? 88 : 152,
    child: StreamingTraceOverlayCard(snapshot: snapshot),
  ),
```

- [ ] **Step 6: Run widget tests to verify overlay rendering passes**

Run: `flutter test test/widgets/debug/streaming_trace_overlay_card_test.dart test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/chat_blocks/streaming_response_block.dart \
  lib/widgets/debug/streaming_trace_overlay_card.dart \
  lib/pages/chat_page.dart \
  test/widgets/debug/streaming_trace_overlay_card_test.dart \
  test/pages/chat_page_test.dart
git commit -m "feat: add streaming trace overlay card"
```

## Task 4: Connect Long-Press Toggle to Running Tail and Add End-to-End UI Regressions

**Files:**
- Modify: `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `test/widgets/chat_blocks/latest_message_running_status_tail_test.dart`
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/pages/chat_page_test.dart`

- [ ] **Step 1: Write failing long-press toggle tests**

```dart
testWidgets('long press running tail opens overlay and second long press closes it', (tester) async {
  await tester.pumpWidget(buildChatPageWithActiveRunningTail());

  final tail = find.byKey(const ValueKey('latest-message-running-tail'));
  await tester.longPress(tail);
  await tester.pumpAndSettle();
  expect(find.byType(StreamingTraceOverlayCard), findsOneWidget);

  await tester.longPress(tail);
  await tester.pumpAndSettle();
  expect(find.byType(StreamingTraceOverlayCard), findsNothing);
});

testWidgets('overlay auto closes when running tail disappears', (tester) async {
  final controller = buildHarnessWithStreamingThenFinalTakeover();
  await tester.pumpWidget(buildChatPage(harness: controller));

  await tester.longPress(find.byKey(const ValueKey('latest-message-running-tail')));
  await tester.pumpAndSettle();
  expect(find.byType(StreamingTraceOverlayCard), findsOneWidget);

  await controller.finishTurn();
  await tester.pumpAndSettle();
  expect(find.byType(StreamingTraceOverlayCard), findsNothing);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/chat_blocks/latest_message_running_status_tail_test.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: FAIL because the running tail does not yet expose a toggle callback and the page has no overlay visibility coordination.

- [ ] **Step 3: Add long-press callback to the tail and row**

```dart
class LatestMessageRunningStatusTail extends StatelessWidget {
  const LatestMessageRunningStatusTail({
    super.key,
    required this.statusText,
    this.onLongPress,
  });

  final VoidCallback? onLongPress;
}

// ChatTimelineRow
LatestMessageRunningStatusTail(
  statusText: item.runningTailText!,
  onLongPress: onToggleStreamingTraceOverlay,
)
```

- [ ] **Step 4: Resolve one stable running-tail anchor id and wire page-level toggle**

```dart
final anchorId = 'running-tail:${item.stableKey}';

ref.read(streamingTraceOverlayCoordinatorProvider.notifier).toggle(
  anchorId: anchorId,
  hasActiveTrace: snapshot != null,
);
```

- [ ] **Step 5: Auto-close overlay when tail or active trace disappears**

```dart
ref.listen(chatTimelineProjectionProvider, (previous, next) {
  if (next.assistantBlocks.isEmpty || next == previousWithoutRunningTail) {
    ref.read(streamingTraceOverlayCoordinatorProvider.notifier)
        .closeIfAnchorDisappeared();
  }
});
```

- [ ] **Step 6: Update docs**

Add to `README.md`:

```md
- 长按当前运行中状态条可打开轻量流式时间线浮层；再次长按同一状态条关闭。该浮层只消费 runtime-only trace projection，不进入 transcript truth。
```

Add to `AGENTS.md`:

```md
- 流式时间线可视化属于 runtime-only observability，不应写入 `messages` / `chat_events` / `chat_turn_steps` 作为用户可见历史真相。
```

- [ ] **Step 7: Run end-to-end widget regressions**

Run: `flutter test test/widgets/chat_blocks/latest_message_running_status_tail_test.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 8: Run broader verification**

Run: `flutter test test/services/debug/streaming_trace_recorder_test.dart test/services/chat_timeline_projection_service_test.dart test/widgets/debug/streaming_trace_overlay_card_test.dart test/widgets/chat_blocks/latest_message_running_status_tail_test.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/chat_blocks/latest_message_running_status_tail.dart \
  lib/widgets/chat_timeline/chat_timeline_row.dart \
  lib/widgets/chat_message_list.dart \
  lib/providers/chat_ui_providers.dart \
  README.md AGENTS.md \
  test/widgets/chat_blocks/latest_message_running_status_tail_test.dart \
  test/widgets/chat_message_list_test.dart \
  test/pages/chat_page_test.dart
git commit -m "feat: toggle streaming trace overlay from running tail"
```

## Final Verification

- [ ] **Step 1: Run the focused full suite for this feature**

Run: `flutter test test/services/debug/streaming_trace_recorder_test.dart test/services/chat_timeline_projection_service_test.dart test/widgets/debug/streaming_trace_overlay_card_test.dart test/widgets/chat_blocks/latest_message_running_status_tail_test.dart test/widgets/chat_message_list_test.dart test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 2: Manually verify in app**

Run: `flutter run`

Manual checks:

- 发送一条会触发流式回复的消息
- 确认默认页面没有新增常驻调试入口
- 运行中状态条出现后长按一次，浮层出现
- 再次长按同一状态条，浮层关闭
- 浮层中能看到 `stream.event_received -> ui.first_visible -> final.takeover` 关键节点
- 回复结束后，若状态条消失，浮层自动关闭

- [ ] **Step 3: Land the cohesive change**

```bash
git add lib/models/debug/streaming_trace_snapshot.dart \
  lib/services/debug/streaming_trace_recorder.dart \
  lib/models/llm/configurable_http_llm.dart \
  lib/services/runtime_streaming_preview_projector.dart \
  lib/providers/chat_ui_providers.dart \
  lib/services/chat_timeline_projection_service.dart \
  lib/services/turn_projection_dispatcher.dart \
  lib/widgets/chat_blocks/streaming_response_block.dart \
  lib/widgets/debug/streaming_trace_overlay_card.dart \
  lib/widgets/chat_blocks/latest_message_running_status_tail.dart \
  lib/widgets/chat_timeline/chat_timeline_row.dart \
  lib/widgets/chat_message_list.dart \
  lib/pages/chat_page.dart \
  README.md AGENTS.md \
  test/services/debug/streaming_trace_recorder_test.dart \
  test/services/chat_timeline_projection_service_test.dart \
  test/widgets/debug/streaming_trace_overlay_card_test.dart \
  test/widgets/chat_blocks/latest_message_running_status_tail_test.dart \
  test/widgets/chat_message_list_test.dart \
  test/pages/chat_page_test.dart
git commit -m "feat: add streaming trace overlay visualization"
```

## Notes

- 本计划故意不把 `DebugTurnInspector` 作为第一版主入口；后续若要扩展完整明细，应复用同一份 `StreamingTraceSnapshot` 而不是再造一条平行数据链。
- `preview.state_committed` 是正式阶段名；不要把当前实现细节 `flush` 暴露为长期观测语义。
- 若实现中发现 `StreamingResponseBlock` 难以稳定拿到 `traceId` / `turnId`，优先在 projection block payload 中补结构化字段，而不是在 widget 层回扫 `messagesProvider` 猜测来源。
