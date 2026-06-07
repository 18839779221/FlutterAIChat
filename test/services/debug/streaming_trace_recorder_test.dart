import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingTraceRecorder', () {
    test('records ordered streaming stages into one active snapshot', () {
      final recorder = StreamingTraceRecorder();

      recorder.recordStage(
        traceId: 'trace_1',
        turnId: 'turn_1',
        stage: StreamingTraceStage.streamEventReceived,
        details: const {'blockType': 'text'},
        timestamp: DateTime(2026, 5, 31, 10, 0, 0),
      );
      recorder.recordStage(
        traceId: 'trace_1',
        turnId: 'turn_1',
        stage: StreamingTraceStage.previewStateCommitted,
        details: const {'textLength': 12},
        timestamp: DateTime(2026, 5, 31, 10, 0, 0, 50),
      );

      final snapshot = recorder.activeSnapshot;
      expect(snapshot?.traceId, 'trace_1');
      expect(snapshot?.entries.length, 2);
      expect(
        snapshot?.currentStage,
        StreamingTraceStage.previewStateCommitted,
      );
      expect(snapshot?.entries.last.elapsedMsFromStart, 50);
    });

    test('retains model request stage details for timeline segmentation', () {
      final recorder = StreamingTraceRecorder();
      final startedAt = DateTime(2026, 5, 31, 10, 0, 0);

      recorder.recordStage(
        traceId: 'trace_model',
        turnId: 'turn_42',
        stage: StreamingTraceStage.modelRequestStarted,
        timestamp: startedAt,
        details: const {
          'requestId': 'planner_42_1',
          'phase': 'tool_call',
          'toolName': 'create_artifact',
        },
      );
      recorder.recordStage(
        traceId: 'trace_model',
        turnId: 'turn_42',
        stage: StreamingTraceStage.modelFirstChunk,
        timestamp: startedAt.add(const Duration(milliseconds: 2400)),
        details: const {
          'requestId': 'planner_42_1',
          'phase': 'tool_call',
          'toolName': 'create_artifact',
        },
      );
      recorder.recordStage(
        traceId: 'trace_model',
        turnId: 'turn_42',
        stage: StreamingTraceStage.modelRequestCompleted,
        timestamp: startedAt.add(const Duration(milliseconds: 5100)),
        details: const {
          'requestId': 'planner_42_1',
          'phase': 'tool_call',
          'toolName': 'create_artifact',
        },
      );

      final snapshot = recorder.activeSnapshot;
      expect(snapshot?.entries.length, 3);
      expect(snapshot?.entries.first.details['requestId'], 'planner_42_1');
      expect(snapshot?.entries.first.details['phase'], 'tool_call');
      expect(snapshot?.entries.first.details['toolName'], 'create_artifact');
      expect(
        snapshot?.entries.last.stage,
        StreamingTraceStage.modelRequestCompleted,
      );
    });

    test('emits persistent logs only for high-signal persisted stages', () {
      final persisted = <Map<String, dynamic>>[];
      final recorder = StreamingTraceRecorder(
        persistentLogger: (message, data) {
          persisted.add({
            'message': message,
            'data': data,
          });
        },
      );
      final startedAt = DateTime(2026, 6, 7, 10, 0, 0);

      recorder.recordStage(
        traceId: 'trace_persisted',
        turnId: '42',
        stage: StreamingTraceStage.turnStarted,
        timestamp: startedAt,
      );
      recorder.recordStage(
        traceId: 'trace_persisted',
        turnId: '42',
        stage: StreamingTraceStage.uiUpdated,
        timestamp: startedAt.add(const Duration(milliseconds: 50)),
        details: const {'previewText': 'partial'},
      );
      recorder.recordStage(
        traceId: 'trace_persisted',
        turnId: '42',
        stage: StreamingTraceStage.uiFirstVisible,
        timestamp: startedAt.add(const Duration(milliseconds: 1200)),
        details: const {'previewText': 'hello'},
      );
      recorder.recordStage(
        traceId: 'trace_persisted',
        turnId: '42',
        stage: StreamingTraceStage.finalTakeover,
        timestamp: startedAt.add(const Duration(milliseconds: 1800)),
        details: const {'previewText': 'hello world'},
      );
      recorder.markCompleted(
        traceId: 'trace_persisted',
        takeoverAt: startedAt.add(const Duration(milliseconds: 1800)),
      );

      expect(
        persisted.map((entry) => entry['message']),
        [
          'streaming.trace.stage',
          'streaming.trace.stage',
          'streaming.trace.stage',
          'streaming.trace.lifecycle',
        ],
      );
      expect(
        persisted
            .where(
              (entry) =>
                  (entry['data'] as Map<String, dynamic>)['stage'] ==
                  StreamingTraceStage.uiUpdated.name,
            )
            .isEmpty,
        isTrue,
      );
      expect(
        (persisted[1]['data'] as Map<String, dynamic>)['stage'],
        StreamingTraceStage.uiFirstVisible.name,
      );
      expect(
        (persisted.last['data'] as Map<String, dynamic>)['lifecycleStatus'],
        StreamingTraceLifecycleStatus.completed.name,
      );
    });
  });

  group('StreamingTraceOverlayController', () {
    test('show opens only with active trace and close dismisses overlay', () {
      final controller = StreamingTraceOverlayController();

      controller.show(anchorId: 'tail_1', hasActiveTrace: false);
      expect(controller.state.isVisible, isFalse);

      controller.show(anchorId: 'tail_1', hasActiveTrace: true);
      expect(controller.state.isVisible, isTrue);
      expect(controller.state.anchorId, 'tail_1');

      controller.close();
      expect(controller.state.isVisible, isFalse);
      expect(controller.state.anchorId, isNull);
    });
  });
}
