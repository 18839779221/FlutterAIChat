import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:ai_chat/services/debug/streaming_visibility_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingVisibilityReporter', () {
    test('records artifact runtime preview visibility with derived trace id', () {
      final recorder = StreamingTraceRecorder();
      final reporter = StreamingVisibilityReporter();
      final timestamp = DateTime(2026, 6, 8, 10, 0, 0);

      reporter.recordArtifactPreviewFirstVisible(
        recorder: recorder,
        turnId: '42',
        artifactId: 'ios-architecture',
        sourcePath: 'runtime://create_artifact/call_1',
        isRuntimePreview: true,
        sourceLength: 512,
        timestamp: timestamp,
      );

      final snapshot = recorder.activeSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.traceId, 'turn_42_stream');
      expect(snapshot.turnId, '42');
      expect(snapshot.firstVisibleAt, timestamp);
      expect(snapshot.currentStage, StreamingTraceStage.uiFirstVisible);
      expect(snapshot.entries, hasLength(1));
      expect(
        snapshot.entries.single.details,
        containsPair('source', 'artifact_runtime_preview'),
      );
      expect(
        snapshot.entries.single.details,
        containsPair('artifactId', 'ios-architecture'),
      );
      expect(
        snapshot.entries.single.details,
        containsPair('sourcePath', 'runtime://create_artifact/call_1'),
      );
    });

    test('keeps the earliest visible timestamp across multiple UI surfaces', () {
      final recorder = StreamingTraceRecorder();
      final reporter = StreamingVisibilityReporter();
      final artifactVisibleAt = DateTime(2026, 6, 8, 10, 0, 0);
      final finalTextVisibleAt = artifactVisibleAt.add(
        const Duration(milliseconds: 1800),
      );

      reporter.recordArtifactPreviewFirstVisible(
        recorder: recorder,
        turnId: '43',
        artifactId: 'android-architecture',
        sourcePath: 'runtime://create_artifact/call_2',
        isRuntimePreview: true,
        sourceLength: 256,
        timestamp: artifactVisibleAt,
      );
      recorder.recordStage(
        traceId: 'turn_43_stream',
        turnId: '43',
        stage: StreamingTraceStage.uiFirstVisible,
        timestamp: finalTextVisibleAt,
        details: const {
          'source': 'final_response_text',
          'previewText': '已生成可视化',
        },
      );

      final snapshot = recorder.activeSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.firstVisibleAt, artifactVisibleAt);
      expect(snapshot.entries, hasLength(2));
      expect(snapshot.entries.first.details['source'], 'artifact_runtime_preview');
      expect(snapshot.entries.last.details['source'], 'final_response_text');
    });
  });
}
