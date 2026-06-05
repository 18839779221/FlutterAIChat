import 'package:ai_chat/models/artifact/artifact_render_session_snapshot.dart';
import 'package:ai_chat/services/artifact/artifact_render_session_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactRenderSessionRecorder', () {
    test('marks session anomalous when applied height drops by more than 30px',
        () {
      final recorder = ArtifactRenderSessionRecorder();
      const sessionId = 'turn_1:artifact_1:0';

      recorder.startSession(
        sessionId: sessionId,
        turnId: 'turn_1',
        artifactId: 'artifact_1',
        providerCallId: 'call_1',
        sourcePath: 'runtime://artifact_1',
        phase: ArtifactRenderPhase.runtime,
        isRuntimePreview: true,
        timestamp: DateTime(2026, 6, 6, 10, 0, 0),
      );
      recorder.recordHeightApplied(
        sessionId: sessionId,
        appliedHeight: 280,
        isPreviewTruncated: false,
        timestamp: DateTime(2026, 6, 6, 10, 0, 1),
      );
      recorder.recordHeightApplied(
        sessionId: sessionId,
        appliedHeight: 240,
        isPreviewTruncated: false,
        timestamp: DateTime(2026, 6, 6, 10, 0, 2),
      );

      final snapshot = recorder.finishSession(
        sessionId: sessionId,
        timestamp: DateTime(2026, 6, 6, 10, 0, 3),
      );

      expect(snapshot.verdict, ArtifactRenderSessionVerdict.anomalous);
      expect(
        snapshot.anomalyCodes,
        contains('artifact_height_drop_over_30px'),
      );
      expect(snapshot.largestDropPx, 40);
    });

    test('flags first render in final second when stream lasts longer than 3s',
        () {
      final recorder = ArtifactRenderSessionRecorder();
      const sessionId = 'turn_1:artifact_1:0';
      final startedAt = DateTime(2026, 6, 6, 10, 0, 0);

      recorder.startSession(
        sessionId: sessionId,
        turnId: 'turn_1',
        artifactId: 'artifact_1',
        sourcePath: 'runtime://artifact_1',
        phase: ArtifactRenderPhase.runtime,
        isRuntimePreview: true,
        timestamp: startedAt,
      );
      recorder.recordSourceProgressed(
        sessionId: sessionId,
        sourceLength: 120,
        deltaLength: 120,
        timestamp: startedAt.add(const Duration(milliseconds: 300)),
      );
      recorder.recordRuntimeApplyCompleted(
        sessionId: sessionId,
        sourceLength: 600,
        result: 'success',
        timestamp: startedAt.add(const Duration(milliseconds: 2600)),
      );
      recorder.recordDomCommit(
        sessionId: sessionId,
        sourceLength: 600,
        artifactRectHeight: 180,
        timestamp: startedAt.add(const Duration(milliseconds: 3200)),
      );
      recorder.recordHeightApplied(
        sessionId: sessionId,
        appliedHeight: 200,
        isPreviewTruncated: false,
        timestamp: startedAt.add(const Duration(milliseconds: 3250)),
      );

      final snapshot = recorder.finishSession(
        sessionId: sessionId,
        timestamp: startedAt.add(const Duration(milliseconds: 3600)),
      );

      expect(
        snapshot.anomalyCodes,
        contains('artifact_first_render_in_final_second'),
      );
      expect(snapshot.firstSuccessfulRenderAtMs, 3250);
    });

    test('classifies final takeover drop before generic overshoot drop', () {
      final recorder = ArtifactRenderSessionRecorder();
      const sessionId = 'turn_1:artifact_1:0';
      final startedAt = DateTime(2026, 6, 6, 10, 0, 0);

      recorder.startSession(
        sessionId: sessionId,
        turnId: 'turn_1',
        artifactId: 'artifact_1',
        sourcePath: 'runtime://artifact_1',
        phase: ArtifactRenderPhase.runtime,
        isRuntimePreview: true,
        timestamp: startedAt,
      );
      recorder.recordHeightApplied(
        sessionId: sessionId,
        appliedHeight: 420,
        isPreviewTruncated: false,
        timestamp: startedAt.add(const Duration(milliseconds: 800)),
      );
      recorder.recordFinalTakeover(
        sessionId: sessionId,
        sourceLength: 700,
        timestamp: startedAt.add(const Duration(milliseconds: 900)),
      );
      recorder.recordHeightApplied(
        sessionId: sessionId,
        appliedHeight: 360,
        isPreviewTruncated: false,
        timestamp: startedAt.add(const Duration(milliseconds: 950)),
      );

      final snapshot = recorder.finishSession(
        sessionId: sessionId,
        timestamp: startedAt.add(const Duration(milliseconds: 1200)),
      );

      expect(
        snapshot.heightPattern,
        ArtifactRenderHeightPattern.finalTakeoverDrop,
      );
    });
  });
}
