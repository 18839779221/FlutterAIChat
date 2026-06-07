import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/services/debug/streaming_turn_timeline_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingTurnTimelineBuilder', () {
    test('builds current-turn timeline from turn start through final answer', () {
      final startedAt = DateTime(2026, 5, 31, 12, 0, 0);
      final snapshot = StreamingTraceSnapshot(
        traceId: 'trace_1',
        turnId: 'turn_1',
        status: StreamingTraceLifecycleStatus.completed,
        currentStage: StreamingTraceStage.finalTakeover,
        summaryText: 'done',
        startedAt: startedAt,
        takeoverAt: startedAt.add(const Duration(milliseconds: 6200)),
        entries: [
          StreamingTraceEntry(
            eventId: 'e0',
            traceId: 'trace_1',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            elapsedMsFromStart: 0,
            title: 'turnStarted',
          ),
          StreamingTraceEntry(
            eventId: 'e1',
            traceId: 'trace_1',
            stage: StreamingTraceStage.modelRequestStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 200)),
            elapsedMsFromStart: 200,
            title: 'modelRequestStarted',
            details: const {'phase': 'tool_call', 'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e2',
            traceId: 'trace_1',
            stage: StreamingTraceStage.modelFirstChunk,
            timestamp: startedAt.add(const Duration(milliseconds: 900)),
            elapsedMsFromStart: 900,
            title: 'modelFirstChunk',
            details: const {'phase': 'tool_call', 'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e3',
            traceId: 'trace_1',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 1200)),
            elapsedMsFromStart: 1200,
            title: 'toolCallStarted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e4',
            traceId: 'trace_1',
            stage: StreamingTraceStage.toolCallCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 3100)),
            elapsedMsFromStart: 3100,
            title: 'toolCallCompleted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e5',
            traceId: 'trace_1',
            stage: StreamingTraceStage.modelRequestCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 3400)),
            elapsedMsFromStart: 3400,
            title: 'modelRequestCompleted',
            details: const {'phase': 'tool_call', 'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e6',
            traceId: 'trace_1',
            stage: StreamingTraceStage.modelRequestStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 3600)),
            elapsedMsFromStart: 3600,
            title: 'modelRequestStarted',
            details: const {'phase': 'final_answer'},
          ),
          StreamingTraceEntry(
            eventId: 'e7',
            traceId: 'trace_1',
            stage: StreamingTraceStage.modelFirstChunk,
            timestamp: startedAt.add(const Duration(milliseconds: 4300)),
            elapsedMsFromStart: 4300,
            title: 'modelFirstChunk',
            details: const {'phase': 'final_answer'},
          ),
          StreamingTraceEntry(
            eventId: 'e8',
            traceId: 'trace_1',
            stage: StreamingTraceStage.uiFirstVisible,
            timestamp: startedAt.add(const Duration(milliseconds: 4300)),
            elapsedMsFromStart: 4300,
            title: 'uiFirstVisible',
            details: const {'previewText': '今天的主要变化是'},
          ),
          StreamingTraceEntry(
            eventId: 'e9',
            traceId: 'trace_1',
            stage: StreamingTraceStage.modelRequestCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 6200)),
            elapsedMsFromStart: 6200,
            title: 'modelRequestCompleted',
            details: const {'phase': 'final_answer'},
          ),
          StreamingTraceEntry(
            eventId: 'e10',
            traceId: 'trace_1',
            stage: StreamingTraceStage.finalTakeover,
            timestamp: startedAt.add(const Duration(milliseconds: 6200)),
            elapsedMsFromStart: 6200,
            title: 'finalTakeover',
            details: const {'previewText': '今天的主要变化是'},
          ),
        ],
      );

      final timeline = const StreamingTurnTimelineBuilder().build(snapshot);

      expect(timeline.totalElapsedMs, 6200);
      expect(timeline.currentStatusTitle, '已完成');
      expect(
        timeline.segments.map((segment) => segment.title).toList(),
        ['等待模型响应', '调用 web_search', '步骤间等待', '回复生成中'],
      );
      expect(
        timeline.segments.map((segment) => segment.durationMs).toList(),
        [1200, 1900, 1200, 1900],
      );
      expect(timeline.segments.last.detail, '正在生成：今天的主要变化是');
      expect(timeline.segments[1].modelFirstChunkDelayMs, 700);
      expect(timeline.segments[1].modelStreamingDurationMs, 2500);
      expect(timeline.segments.last.modelFirstChunkDelayMs, 700);
      expect(timeline.segments.last.modelStreamingDurationMs, 1900);
    });

    test('attaches model metrics to ongoing tool and final answer segments', () {
      final startedAt = DateTime(2026, 5, 31, 12, 0, 0);
      final snapshot = StreamingTraceSnapshot(
        traceId: 'trace_metrics',
        turnId: 'turn_metrics',
        status: StreamingTraceLifecycleStatus.running,
        currentStage: StreamingTraceStage.uiUpdated,
        summaryText: 'running',
        startedAt: startedAt,
        entries: [
          StreamingTraceEntry(
            eventId: 'e0',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            elapsedMsFromStart: 0,
            title: 'turnStarted',
          ),
          StreamingTraceEntry(
            eventId: 'e1',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.modelRequestStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 100)),
            elapsedMsFromStart: 100,
            title: 'modelRequestStarted',
            details: const {'phase': 'tool_call', 'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e2',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.modelFirstChunk,
            timestamp: startedAt.add(const Duration(milliseconds: 2400)),
            elapsedMsFromStart: 2400,
            title: 'modelFirstChunk',
            details: const {'phase': 'tool_call', 'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e3',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 2500)),
            elapsedMsFromStart: 2500,
            title: 'toolCallStarted',
            details: const {'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e4',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.toolCallCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 5000)),
            elapsedMsFromStart: 5000,
            title: 'toolCallCompleted',
            details: const {'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e5',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.modelRequestCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 5200)),
            elapsedMsFromStart: 5200,
            title: 'modelRequestCompleted',
            details: const {'phase': 'tool_call', 'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e6',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.modelRequestStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 5400)),
            elapsedMsFromStart: 5400,
            title: 'modelRequestStarted',
            details: const {'phase': 'final_answer'},
          ),
          StreamingTraceEntry(
            eventId: 'e7',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.modelFirstChunk,
            timestamp: startedAt.add(const Duration(milliseconds: 8600)),
            elapsedMsFromStart: 8600,
            title: 'modelFirstChunk',
            details: const {'phase': 'final_answer'},
          ),
          StreamingTraceEntry(
            eventId: 'e8',
            traceId: 'trace_metrics',
            stage: StreamingTraceStage.uiFirstVisible,
            timestamp: startedAt.add(const Duration(milliseconds: 8600)),
            elapsedMsFromStart: 8600,
            title: 'uiFirstVisible',
            details: const {'previewText': '已开始输出'},
          ),
        ],
      );

      final timeline = const StreamingTurnTimelineBuilder().build(
        snapshot,
        now: startedAt.add(const Duration(milliseconds: 9800)),
      );

      expect(timeline.segments[1].modelFirstChunkDelayMs, 2300);
      expect(timeline.segments[1].modelStreamingDurationMs, 2800);
      expect(timeline.segments.last.title, '回复生成中');
      expect(timeline.segments.last.modelFirstChunkDelayMs, 3200);
      expect(timeline.segments.last.modelStreamingDurationMs, 1200);
      expect(timeline.segments.last.isOngoing, isTrue);
    });

    test('splits serial tool calls into separate duration segments', () {
      final startedAt = DateTime(2026, 5, 31, 12, 0, 0);
      final snapshot = StreamingTraceSnapshot(
        traceId: 'trace_2',
        turnId: 'turn_2',
        status: StreamingTraceLifecycleStatus.running,
        currentStage: StreamingTraceStage.toolCallStarted,
        summaryText: 'tool',
        startedAt: startedAt,
        entries: [
          StreamingTraceEntry(
            eventId: 'e0',
            traceId: 'trace_2',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            elapsedMsFromStart: 0,
            title: 'turnStarted',
          ),
          StreamingTraceEntry(
            eventId: 'e1',
            traceId: 'trace_2',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 800)),
            elapsedMsFromStart: 800,
            title: 'toolCallStarted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e2',
            traceId: 'trace_2',
            stage: StreamingTraceStage.toolCallCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 1900)),
            elapsedMsFromStart: 1900,
            title: 'toolCallCompleted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e3',
            traceId: 'trace_2',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 2400)),
            elapsedMsFromStart: 2400,
            title: 'toolCallStarted',
            details: const {'toolName': 'fetch_webpage'},
          ),
        ],
      );

      final timeline = const StreamingTurnTimelineBuilder().build(
        snapshot,
        now: startedAt.add(const Duration(milliseconds: 4800)),
      );

      expect(
        timeline.segments.map((segment) => segment.title).toList(),
        ['等待模型响应', '调用 web_search', '步骤间等待', '调用 fetch_webpage'],
      );
      expect(timeline.segments[1].durationMs, 1100);
      expect(timeline.segments[3].durationMs, 2400);
      expect(timeline.segments[3].isOngoing, isTrue);
      expect(timeline.currentStatusTitle, '调用 fetch_webpage');
    });

    test('does not double count when final answer becomes visible before prior segment ends', () {
      final startedAt = DateTime(2026, 5, 31, 12, 0, 0);
      final snapshot = StreamingTraceSnapshot(
        traceId: 'trace_3',
        turnId: 'turn_3',
        status: StreamingTraceLifecycleStatus.completed,
        currentStage: StreamingTraceStage.finalTakeover,
        summaryText: 'done',
        startedAt: startedAt,
        takeoverAt: startedAt.add(const Duration(milliseconds: 6200)),
        entries: [
          StreamingTraceEntry(
            eventId: 'e0',
            traceId: 'trace_3',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            elapsedMsFromStart: 0,
            title: 'turnStarted',
          ),
          StreamingTraceEntry(
            eventId: 'e1',
            traceId: 'trace_3',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 1200)),
            elapsedMsFromStart: 1200,
            title: 'toolCallStarted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e2',
            traceId: 'trace_3',
            stage: StreamingTraceStage.uiFirstVisible,
            timestamp: startedAt.add(const Duration(milliseconds: 2600)),
            elapsedMsFromStart: 2600,
            title: 'uiFirstVisible',
            details: const {'previewText': '今天的主要变化是'},
          ),
          StreamingTraceEntry(
            eventId: 'e3',
            traceId: 'trace_3',
            stage: StreamingTraceStage.toolCallCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 3100)),
            elapsedMsFromStart: 3100,
            title: 'toolCallCompleted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e4',
            traceId: 'trace_3',
            stage: StreamingTraceStage.finalTakeover,
            timestamp: startedAt.add(const Duration(milliseconds: 6200)),
            elapsedMsFromStart: 6200,
            title: 'finalTakeover',
            details: const {'previewText': '今天的主要变化是'},
          ),
        ],
      );

      final timeline = const StreamingTurnTimelineBuilder().build(snapshot);
      final summedDurationMs = timeline.segments.fold<int>(
        0,
        (sum, segment) => sum + segment.durationMs,
      );

      expect(timeline.totalElapsedMs, 6200);
      expect(summedDurationMs, timeline.totalElapsedMs);
      expect(
        timeline.segments.map((segment) => segment.durationMs).toList(),
        [1200, 1900, 3100],
      );
    });

    test('extends tool span when preview tool-use streaming exceeds threshold', () {
      final startedAt = DateTime(2026, 5, 31, 12, 0, 0);
      final snapshot = StreamingTraceSnapshot(
        traceId: 'trace_4',
        turnId: 'turn_4',
        status: StreamingTraceLifecycleStatus.completed,
        currentStage: StreamingTraceStage.finalTakeover,
        summaryText: 'done',
        startedAt: startedAt,
        takeoverAt: startedAt.add(const Duration(milliseconds: 4000)),
        entries: [
          StreamingTraceEntry(
            eventId: 'e0',
            traceId: 'trace_4',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            elapsedMsFromStart: 0,
            title: 'turnStarted',
          ),
          StreamingTraceEntry(
            eventId: 'e1',
            traceId: 'trace_4',
            stage: StreamingTraceStage.toolCallStreamStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 1000)),
            elapsedMsFromStart: 1000,
            title: 'toolCallStreamStarted',
            details: const {'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e2',
            traceId: 'trace_4',
            stage: StreamingTraceStage.toolCallStreamCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 1305)),
            elapsedMsFromStart: 1305,
            title: 'toolCallStreamCompleted',
            details: const {'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e3',
            traceId: 'trace_4',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 1310)),
            elapsedMsFromStart: 1310,
            title: 'toolCallStarted',
            details: const {'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e4',
            traceId: 'trace_4',
            stage: StreamingTraceStage.toolCallCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 3000)),
            elapsedMsFromStart: 3000,
            title: 'toolCallCompleted',
            details: const {'toolName': 'create_artifact'},
          ),
          StreamingTraceEntry(
            eventId: 'e5',
            traceId: 'trace_4',
            stage: StreamingTraceStage.uiFirstVisible,
            timestamp: startedAt.add(const Duration(milliseconds: 3300)),
            elapsedMsFromStart: 3300,
            title: 'uiFirstVisible',
            details: const {'previewText': 'Artifact 已准备好'},
          ),
          StreamingTraceEntry(
            eventId: 'e6',
            traceId: 'trace_4',
            stage: StreamingTraceStage.finalTakeover,
            timestamp: startedAt.add(const Duration(milliseconds: 4000)),
            elapsedMsFromStart: 4000,
            title: 'finalTakeover',
            details: const {'previewText': 'Artifact 已准备好'},
          ),
        ],
      );

      final timeline = const StreamingTurnTimelineBuilder().build(snapshot);

      expect(
        timeline.segments.map((segment) => segment.title).toList(),
        ['等待模型响应', '调用 create_artifact', '步骤间等待', '回复生成中'],
      );
      expect(
        timeline.segments.map((segment) => segment.durationMs).toList(),
        [1000, 2000, 300, 700],
      );
    });

    test('ignores preview tool-use streaming under threshold', () {
      final startedAt = DateTime(2026, 5, 31, 12, 0, 0);
      final snapshot = StreamingTraceSnapshot(
        traceId: 'trace_5',
        turnId: 'turn_5',
        status: StreamingTraceLifecycleStatus.completed,
        currentStage: StreamingTraceStage.finalTakeover,
        summaryText: 'done',
        startedAt: startedAt,
        takeoverAt: startedAt.add(const Duration(milliseconds: 4000)),
        entries: [
          StreamingTraceEntry(
            eventId: 'e0',
            traceId: 'trace_5',
            stage: StreamingTraceStage.turnStarted,
            timestamp: startedAt,
            elapsedMsFromStart: 0,
            title: 'turnStarted',
          ),
          StreamingTraceEntry(
            eventId: 'e1',
            traceId: 'trace_5',
            stage: StreamingTraceStage.toolCallStreamStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 1000)),
            elapsedMsFromStart: 1000,
            title: 'toolCallStreamStarted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e2',
            traceId: 'trace_5',
            stage: StreamingTraceStage.toolCallStreamCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 1010)),
            elapsedMsFromStart: 1010,
            title: 'toolCallStreamCompleted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e3',
            traceId: 'trace_5',
            stage: StreamingTraceStage.toolCallStarted,
            timestamp: startedAt.add(const Duration(milliseconds: 1300)),
            elapsedMsFromStart: 1300,
            title: 'toolCallStarted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e4',
            traceId: 'trace_5',
            stage: StreamingTraceStage.toolCallCompleted,
            timestamp: startedAt.add(const Duration(milliseconds: 3000)),
            elapsedMsFromStart: 3000,
            title: 'toolCallCompleted',
            details: const {'toolName': 'web_search'},
          ),
          StreamingTraceEntry(
            eventId: 'e5',
            traceId: 'trace_5',
            stage: StreamingTraceStage.uiFirstVisible,
            timestamp: startedAt.add(const Duration(milliseconds: 3300)),
            elapsedMsFromStart: 3300,
            title: 'uiFirstVisible',
            details: const {'previewText': '结果如下'},
          ),
          StreamingTraceEntry(
            eventId: 'e6',
            traceId: 'trace_5',
            stage: StreamingTraceStage.finalTakeover,
            timestamp: startedAt.add(const Duration(milliseconds: 4000)),
            elapsedMsFromStart: 4000,
            title: 'finalTakeover',
            details: const {'previewText': '结果如下'},
          ),
        ],
      );

      final timeline = const StreamingTurnTimelineBuilder().build(snapshot);

      expect(
        timeline.segments.map((segment) => segment.durationMs).toList(),
        [1300, 1700, 300, 700],
      );
    });
  });
}
