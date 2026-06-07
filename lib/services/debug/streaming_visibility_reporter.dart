import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';

/// Emits high-signal UI visibility milestones into the streaming trace.
class StreamingVisibilityReporter {
  const StreamingVisibilityReporter();

  void recordArtifactPreviewFirstVisible({
    required StreamingTraceRecorder recorder,
    required String turnId,
    required String artifactId,
    required String sourcePath,
    required bool isRuntimePreview,
    required int sourceLength,
    required DateTime timestamp,
  }) {
    final trimmedTurnId = turnId.trim();
    if (trimmedTurnId.isEmpty) {
      return;
    }
    recorder.recordStage(
      traceId: streamingTraceIdForTurn(trimmedTurnId),
      turnId: trimmedTurnId,
      stage: StreamingTraceStage.uiFirstVisible,
      timestamp: timestamp,
      details: <String, dynamic>{
        'source': isRuntimePreview
            ? 'artifact_runtime_preview'
            : 'artifact_final_preview',
        'artifactId': artifactId,
        'sourcePath': sourcePath,
        'sourceLength': sourceLength,
      },
    );
  }
}
