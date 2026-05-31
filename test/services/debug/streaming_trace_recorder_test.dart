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
