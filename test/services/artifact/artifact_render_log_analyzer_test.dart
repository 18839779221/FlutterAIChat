import 'package:ai_chat/services/artifact/artifact_render_log_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactRenderLogAnalyzer', () {
    const analyzer = ArtifactRenderLogAnalyzer();

    test('groups explicit flowId logs and picks the strongest render attempt',
        () {
      const log = '''
2026-06-06T03:04:07.001652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-runtime flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session turnId=turn_1 artifactId=artifact_1 providerCallId=call_1 sourcePath=runtime://create_artifact/call_1 phase=runtime isRuntimePreview=true
2026-06-06T03:04:07.101652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.source_progressed sessionId=session-runtime flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=1000 deltaLength=1000
2026-06-06T03:04:07.201652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.runtime_apply_started sessionId=session-runtime flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=1000
2026-06-06T03:04:07.301652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.dom_commit sessionId=session-runtime flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=1000 artifactRectHeight=800.0
2026-06-06T03:04:07.401652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session phase=runtime seq=1 appliedHeight=820.0 maxAppliedHeight=820.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-06T03:04:07.501652+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-runtime flowId=turn_1:artifact_1:call_1 verdict=normal anomalyCodes=[] phaseSummary=runtime artifactId=artifact_1 providerCallId=call_1 sourcePath=runtime://create_artifact/call_1 heightPattern=monotonicGrowth maxAppliedHeight=820.0 finalAppliedHeight=820.0 largestDropPx=0.0 heightSampleCount=1 heightAppliedCount=1 sourceProgressCount=1 applyCount=1 domCommitCount=1 totalStreamingDurationMs=500 firstSuccessfulRenderAtMs=320 timeToFirstSuccessfulRenderMs=320 tailWindowMs=180
2026-06-06T03:04:08.001652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-final flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session turnId=turn_1 artifactId=artifact_1 providerCallId=call_1 sourcePath=/workspaces/default/artifacts/a.html phase=finalTakeover isRuntimePreview=false
2026-06-06T03:04:08.101652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.source_progressed sessionId=session-final flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session phase=finalTakeover seq=1 sourceLength=7000 deltaLength=2000
2026-06-06T03:04:08.201652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session phase=finalTakeover seq=1 appliedHeight=2000.0 maxAppliedHeight=2200.0 largestDropPx=200.0 isPreviewTruncated=false
2026-06-06T03:04:08.301652+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.anomaly sessionId=session-final flowId=turn_1:artifact_1:call_1 diagnosticCode=artifact_first_render_in_final_second phase=finalTakeover artifactId=artifact_1 providerCallId=call_1 sourcePath=/workspaces/default/artifacts/a.html details={totalStreamingDurationMs:4200,firstSuccessfulRenderAtMs:3500}
2026-06-06T03:04:08.401652+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-final flowId=turn_1:artifact_1:call_1 verdict=anomalous anomalyCodes=[artifact_first_render_in_final_second] phaseSummary=runtime->finalTakeover artifactId=artifact_1 providerCallId=call_1 sourcePath=/workspaces/default/artifacts/a.html heightPattern=finalTakeoverDrop maxAppliedHeight=2200.0 finalAppliedHeight=2000.0 largestDropPx=200.0 heightSampleCount=3 heightAppliedCount=1 sourceProgressCount=4 applyCount=2 domCommitCount=1 totalStreamingDurationMs=4200 firstSuccessfulRenderAtMs=3500 timeToFirstSuccessfulRenderMs=3500 tailWindowMs=700
''';

      final result = analyzer.analyze(
        log,
        logPath: 'memory.log',
      );

      expect(result.flows, hasLength(1));
      final flow = result.selectedFlow!;
      expect(flow.flowId, 'turn_1:artifact_1:call_1');
      expect(flow.usedDerivedFlowId, isFalse);
      expect(flow.renderAttemptCount, 2);
      expect(flow.uniqueSessionIdCount, 2);
      expect(flow.remountEvidence, contains('multiple_session_ids_same_flow'));
      expect(
          flow.anomalyCodes, contains('artifact_first_render_in_final_second'));
      expect(
        flow.summarySignals,
        containsAll(<String>[
          'remount',
          'late_first_render',
          'final_takeover_drop',
        ]),
      );
      expect(
        flow.summaryLabel,
        'remount + late_first_render + final_takeover_drop',
      );
      expect(
        flow.incidentReport.headline,
        'remount + late_first_render + final_takeover_drop',
      );
      expect(
        flow.incidentReport.findings,
        contains('Flow remounted across 2 attempts and 2 sessionIds.'),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt first rendered in the final 700ms of a 4200ms stream.',
        ),
      );

      final primary = flow.primaryAttempt!;
      expect(primary.sessionId, 'session-final');
      expect(primary.attemptIndex, 2);
      expect(primary.phaseSummary, 'runtime->finalTakeover');
      expect(primary.firstSuccessfulRenderAtMs, 3500);
      expect(primary.tailWindowMs, 700);
      expect(primary.anomalyCodes,
          contains('artifact_first_render_in_final_second'));
    });

    test(
        'falls back to a derived flow and recognizes repeated reused session ids',
        () {
      const log = '''
2026-06-06T03:04:07.001652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session turnId=72_887 artifactId=android-architecture providerCallId=call_function_1 sourcePath=runtime://create_artifact/call_function_1 phase=runtime isRuntimePreview=true
2026-06-06T03:04:07.101652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.source_progressed sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=2674 deltaLength=2674
2026-06-06T03:04:07.201652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.runtime_apply_started sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=2674
2026-06-06T03:04:07.301652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session turnId=72_887 artifactId=android-architecture providerCallId=call_function_1 sourcePath=runtime://create_artifact/call_function_1 phase=runtime isRuntimePreview=true
2026-06-06T03:04:07.401652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.source_progressed sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=7073 deltaLength=7073
2026-06-06T03:04:07.501652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.runtime_apply_started sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=runtime seq=1 sourceLength=7073
2026-06-06T03:04:07.601652+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=72_887:android-architecture:call_function_1:0 verdict=normal anomalyCodes=[] phaseSummary=runtime artifactId=android-architecture providerCallId=call_function_1 sourcePath=runtime://create_artifact/call_function_1 heightPattern=noHeightSignal largestDropPx=0.0 heightSampleCount=0 heightAppliedCount=0 sourceProgressCount=1 applyCount=1 domCommitCount=0 totalStreamingDurationMs=338
2026-06-06T03:04:07.701652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session turnId=72_887 artifactId=android-architecture providerCallId=call_function_1 sourcePath=/workspaces/default/artifacts/android-architecture.html phase=finalTakeover isRuntimePreview=false
2026-06-06T03:04:07.801652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=finalTakeover seq=1 appliedHeight=2429.0 maxAppliedHeight=2429.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-06T03:04:07.901652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=finalTakeover seq=2 appliedHeight=2429.0 maxAppliedHeight=2429.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-06T03:04:08.001652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=72_887:android-architecture:call_function_1:0 reason=diagnose create_artifact render session phase=finalTakeover seq=3 appliedHeight=2429.0 maxAppliedHeight=2429.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-06T03:04:08.101652+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=72_887:android-architecture:call_function_1:0 verdict=normal anomalyCodes=[] phaseSummary=finalTakeover artifactId=android-architecture providerCallId=call_function_1 sourcePath=/workspaces/default/artifacts/android-architecture.html heightPattern=monotonicGrowth maxAppliedHeight=2429.0 finalAppliedHeight=2429.0 largestDropPx=0.0 heightSampleCount=6 heightAppliedCount=3 sourceProgressCount=1 applyCount=0 domCommitCount=0 totalStreamingDurationMs=11192
''';

      final result = analyzer.analyze(
        log,
        logPath: 'legacy.log',
      );

      expect(result.flows, hasLength(1));
      final flow = result.selectedFlow!;
      expect(flow.flowId, '72_887:android-architecture:call_function_1');
      expect(flow.usedDerivedFlowId, isTrue);
      expect(flow.renderAttemptCount, 3);
      expect(flow.uniqueSessionIdCount, 1);
      expect(
        flow.remountEvidence,
        contains('reused_session_id_across_multiple_attempts'),
      );
      expect(flow.summarySignals, <String>['remount']);
      expect(flow.summaryLabel, 'remount');
      expect(flow.incidentReport.headline, 'remount');

      final primary = flow.primaryAttempt!;
      expect(primary.attemptIndex, 3);
      expect(
          primary.sessionId, '72_887:android-architecture:call_function_1:0');
      expect(primary.heightAppliedCount, 3);
      expect(primary.phaseSummary, 'finalTakeover');
      expect(primary.heightPattern, 'monotonicGrowth');
    });

    test(
        'reconstructs height pattern for incomplete attempts from raw height events',
        () {
      const log = '''
2026-06-07T20:53:17.258329+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session turnId=81_995 artifactId=ios-architecture providerCallId=call_2f56f35efcc945b9b416ad35 sourcePath=/workspaces/ws/artifacts/ios-architecture.html phase=finalTakeover isRuntimePreview=false
2026-06-07T20:53:17.260970+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.source_progressed sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session phase=finalTakeover seq=1 sourceLength=7221 deltaLength=7221
2026-06-07T20:53:19.761840+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session phase=finalTakeover seq=1 rawHeight=3127.0 clampedHeight=2493.5064523291244
2026-06-07T20:53:20.139510+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session phase=finalTakeover seq=1 appliedHeight=2493.5064523291244 maxAppliedHeight=2493.5064523291244 largestDropPx=0.0 isPreviewTruncated=true
2026-06-07T20:53:20.382171+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session phase=finalTakeover seq=2 rawHeight=2128.0 clampedHeight=2128.0
2026-06-07T20:53:20.521866+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.anomaly sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 diagnosticCode=artifact_height_drop_over_30px phase=finalTakeover artifactId=ios-architecture providerCallId=call_2f56f35efcc945b9b416ad35 sourcePath=/workspaces/ws/artifacts/ios-architecture.html details={maxAppliedHeight:2493.5064523291244,currentAppliedHeight:2128.0,largestDropPx:365.5064523291244,previousAppliedHeight:2493.5064523291244,sourceLength:7221,hasPendingFinalController:true}
2026-06-07T20:53:20.523604+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session phase=finalTakeover seq=2 appliedHeight=2128.0 maxAppliedHeight=2493.5064523291244 largestDropPx=365.5064523291244 isPreviewTruncated=false
2026-06-07T20:53:20.703047+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=81_995:ios-architecture:call_2f56f35efcc945b9b416ad35 reason=diagnose create_artifact render session phase=finalTakeover seq=3 appliedHeight=2129.0 maxAppliedHeight=2493.5064523291244 largestDropPx=365.5064523291244 isPreviewTruncated=false
''';

      final result = analyzer.analyze(
        log,
        logPath: 'incomplete.log',
      );

      final primary = result.selectedFlow!.primaryAttempt!;
      expect(primary.phaseSummary, 'finalTakeover');
      expect(primary.heightPattern, 'finalTakeoverDrop');
      expect(primary.maxAppliedHeight, closeTo(2493.5064523291244, 0.000001));
      expect(primary.finalAppliedHeight, 2129.0);
      expect(primary.largestDropPx, closeTo(365.5064523291244, 0.000001));
      expect(
        primary.derivedSignals,
        containsAll(<String>[
          'preview_truncation_released',
          'height_drop_after_truncation_release',
        ]),
      );
      expect(primary.largestRecoveryPx, 1.0);
      expect(primary.totalStreamingDurationMs, 3444);
      expect(
        primary.anomalyCodes,
        contains('artifact_height_drop_over_30px'),
      );
      expect(
        result.selectedFlow!.summarySignals,
        containsAll(<String>[
          'final_takeover_drop',
          'truncation_release_drop',
        ]),
      );
      expect(
        result.selectedFlow!.summaryLabel,
        'final_takeover_drop + truncation_release_drop',
      );
      expect(
        result.selectedFlow!.incidentReport.findings,
        contains(
          'Primary final takeover attempt dropped 365.5px after truncation release (2493.5px -> 2129px).',
        ),
      );
    });

    test('detects a meaningful recovery after a height drop within one attempt',
        () {
      const log = '''
2026-06-07T21:10:00.000000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-recover flowId=turn_2:artifact_2:call_2 reason=diagnose create_artifact render session turnId=turn_2 artifactId=artifact_2 providerCallId=call_2 sourcePath=/workspaces/ws/artifacts/a2.html phase=finalTakeover isRuntimePreview=false
2026-06-07T21:10:00.300000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-recover flowId=turn_2:artifact_2:call_2 reason=diagnose create_artifact render session phase=finalTakeover seq=1 appliedHeight=1000.0 maxAppliedHeight=1000.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-07T21:10:00.600000+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.anomaly sessionId=session-recover flowId=turn_2:artifact_2:call_2 diagnosticCode=artifact_height_drop_over_30px phase=finalTakeover artifactId=artifact_2 providerCallId=call_2 sourcePath=/workspaces/ws/artifacts/a2.html details={maxAppliedHeight:1000.0,currentAppliedHeight:920.0,largestDropPx:80.0,previousAppliedHeight:1000.0,sourceLength:2000,hasPendingFinalController:false}
2026-06-07T21:10:00.610000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-recover flowId=turn_2:artifact_2:call_2 reason=diagnose create_artifact render session phase=finalTakeover seq=2 appliedHeight=920.0 maxAppliedHeight=1000.0 largestDropPx=80.0 isPreviewTruncated=false
2026-06-07T21:10:00.900000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-recover flowId=turn_2:artifact_2:call_2 reason=diagnose create_artifact render session phase=finalTakeover seq=3 appliedHeight=980.0 maxAppliedHeight=1000.0 largestDropPx=80.0 isPreviewTruncated=false
''';

      final result = analyzer.analyze(
        log,
        logPath: 'recover.log',
      );

      final primary = result.selectedFlow!.primaryAttempt!;
      expect(
        primary.derivedSignals,
        contains('height_recovered_over_30px_after_drop'),
      );
      expect(primary.largestRecoveryPx, 60.0);
    });

    test(
        'surfaces pending-final height injection and root-scroll outlier from sampled jump context',
        () {
      const log = '''
2026-06-08T00:17:37.425252+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-final flowId=turn_3:artifact_3:call_3 reason=diagnose create_artifact render session turnId=turn_3 artifactId=artifact_3 providerCallId=call_3 sourcePath=/workspaces/ws/artifacts/a3.html phase=finalTakeover isRuntimePreview=false
2026-06-08T00:17:37.430000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-final flowId=turn_3:artifact_3:call_3 reason=diagnose create_artifact render session phase=finalTakeover seq=1 rawHeight=1747.0 clampedHeight=1747.0 heightBasis=artifactRect artifactRectHeight=1746.7 bodyScrollHeight=1747.0 bodyOffsetHeight=1747.0 rootScrollHeight=0.0 rootOffsetHeight=1747.0 controllerId=ctrl_final controllerRole=pendingFinal controllerOrigin=final_preload controllerSourcePath=/workspaces/ws/artifacts/a3.html activeControllerId=ctrl_runtime activeControllerSourcePath=runtime://create_artifact/call_3 pendingFinalControllerId=ctrl_final pendingFinalSourcePath=/workspaces/ws/artifacts/a3.html widgetSourcePath=/workspaces/ws/artifacts/a3.html previousAppliedHeight=863.0 sampleDeltaFromPreviousAppliedPx=884.0 sampledFromPendingFinalController=true hasPendingFinalController=true controllerSourcePathMismatch=false rootScrollOutlierPx=0.0
2026-06-08T00:17:37.439000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=turn_3:artifact_3:call_3 reason=diagnose create_artifact render session phase=finalTakeover seq=1 appliedHeight=1747.0 maxAppliedHeight=1747.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T00:17:37.743176+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-final flowId=turn_3:artifact_3:call_3 reason=diagnose create_artifact render session phase=finalTakeover seq=2 rawHeight=863.0 clampedHeight=863.0 heightBasis=artifactRect artifactRectHeight=862.2 bodyScrollHeight=862.0 bodyOffsetHeight=862.0 rootScrollHeight=1747.0 rootOffsetHeight=862.0 controllerId=ctrl_final controllerRole=pendingFinal controllerOrigin=final_preload controllerSourcePath=/workspaces/ws/artifacts/a3.html activeControllerId=ctrl_runtime activeControllerSourcePath=runtime://create_artifact/call_3 pendingFinalControllerId=ctrl_final pendingFinalSourcePath=/workspaces/ws/artifacts/a3.html widgetSourcePath=/workspaces/ws/artifacts/a3.html previousAppliedHeight=1747.0 sampleDeltaFromPreviousAppliedPx=-884.0 sampledFromPendingFinalController=true hasPendingFinalController=true controllerSourcePathMismatch=false rootScrollOutlierPx=884.8
2026-06-08T00:17:37.866836+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.anomaly sessionId=session-final flowId=turn_3:artifact_3:call_3 diagnosticCode=artifact_height_drop_over_30px phase=finalTakeover artifactId=artifact_3 providerCallId=call_3 sourcePath=/workspaces/ws/artifacts/a3.html details={maxAppliedHeight:1747.0,currentAppliedHeight:863.0,largestDropPx:884.0,previousAppliedHeight:1747.0,sourceLength:4048,hasPendingFinalController:true}
2026-06-08T00:17:37.867303+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=turn_3:artifact_3:call_3 reason=diagnose create_artifact render session phase=finalTakeover seq=2 appliedHeight=863.0 maxAppliedHeight=1747.0 largestDropPx=884.0 isPreviewTruncated=false
2026-06-08T00:17:38.104507+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final flowId=turn_3:artifact_3:call_3 reason=diagnose create_artifact render session phase=finalTakeover seq=3 appliedHeight=863.0 maxAppliedHeight=1747.0 largestDropPx=884.0 isPreviewTruncated=false
2026-06-08T00:17:38.200000+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-final flowId=turn_3:artifact_3:call_3 verdict=anomalous anomalyCodes=[artifact_height_drop_over_30px] phaseSummary=finalTakeover artifactId=artifact_3 providerCallId=call_3 sourcePath=/workspaces/ws/artifacts/a3.html heightPattern=finalTakeoverDrop maxAppliedHeight=1747.0 finalAppliedHeight=863.0 largestDropPx=884.0 heightSampleCount=2 heightAppliedCount=3 sourceProgressCount=1 applyCount=0 domCommitCount=0 totalStreamingDurationMs=775
''';

      final result = analyzer.analyze(
        log,
        logPath: 'sample-context.log',
      );

      final flow = result.selectedFlow!;
      final primary = flow.primaryAttempt!;

      expect(
        primary.derivedSignals,
        containsAll(<String>[
          'pending_final_height_injection_before_takeover',
          'root_scroll_outlier_sampled',
        ]),
      );
      expect(
        flow.summarySignals,
        containsAll(<String>[
          'final_takeover_drop',
          'pending_final_injection',
          'root_scroll_outlier',
        ]),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt sampled a pending-final controller height jump before takeover (863px -> 1747px).',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt saw rootScroll exceed artifact/body metrics by 884.8px during the jump.',
        ),
      );
    });

    test(
        'detects a short-lived runtime sample spike that rolls back before apply',
        () {
      const log = '''
2026-06-08T10:00:00.000000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 reason=diagnose create_artifact render session turnId=turn_4 artifactId=artifact_4 providerCallId=call_4 sourcePath=runtime://create_artifact/call_4 phase=runtime isRuntimePreview=true
2026-06-08T10:00:00.050000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 reason=diagnose create_artifact render session phase=runtime seq=1 appliedHeight=180.0 maxAppliedHeight=180.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T10:00:00.100000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 reason=diagnose create_artifact render session phase=runtime seq=1 rawHeight=180.0 clampedHeight=180.0 heightBasis=artifactRect artifactRectHeight=180.0 artifactOffsetHeight=180.0 artifactScrollHeight=180.0 artifactClientHeight=180.0 bodyScrollHeight=180.0 bodyOffsetHeight=180.0 bodyClientHeight=180.0 rootScrollHeight=180.0 rootOffsetHeight=180.0 rootClientHeight=180.0 previousAppliedHeight=180.0 sampleDeltaFromPreviousAppliedPx=0.0 sampledFromPendingFinalController=false hasPendingFinalController=false controllerSourcePathMismatch=false rootScrollOutlierPx=0.0 artifactRectStretchPx=0.0
2026-06-08T10:00:00.140000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 reason=diagnose create_artifact render session phase=runtime seq=2 rawHeight=220.0 clampedHeight=220.0 heightBasis=artifactRect artifactRectHeight=220.0 artifactOffsetHeight=180.0 artifactScrollHeight=180.0 artifactClientHeight=180.0 bodyScrollHeight=180.0 bodyOffsetHeight=180.0 bodyClientHeight=180.0 rootScrollHeight=180.0 rootOffsetHeight=180.0 rootClientHeight=180.0 previousAppliedHeight=180.0 sampleDeltaFromPreviousAppliedPx=40.0 sampledFromPendingFinalController=false hasPendingFinalController=false controllerSourcePathMismatch=false rootScrollOutlierPx=0.0 artifactRectStretchPx=40.0
2026-06-08T10:00:00.180000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 reason=diagnose create_artifact render session phase=runtime seq=3 rawHeight=180.0 clampedHeight=180.0 heightBasis=artifactRect artifactRectHeight=180.0 artifactOffsetHeight=180.0 artifactScrollHeight=180.0 artifactClientHeight=180.0 bodyScrollHeight=180.0 bodyOffsetHeight=180.0 bodyClientHeight=180.0 rootScrollHeight=180.0 rootOffsetHeight=180.0 rootClientHeight=180.0 previousAppliedHeight=180.0 sampleDeltaFromPreviousAppliedPx=0.0 sampledFromPendingFinalController=false hasPendingFinalController=false controllerSourcePathMismatch=false rootScrollOutlierPx=0.0 artifactRectStretchPx=0.0
2026-06-08T10:00:00.220000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 reason=diagnose create_artifact render session phase=runtime seq=2 appliedHeight=180.0 maxAppliedHeight=180.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T10:00:00.300000+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-runtime-spike flowId=turn_4:artifact_4:call_4 verdict=normal anomalyCodes=[] phaseSummary=runtime artifactId=artifact_4 providerCallId=call_4 sourcePath=runtime://create_artifact/call_4 heightPattern=monotonicGrowth maxAppliedHeight=180.0 finalAppliedHeight=180.0 largestDropPx=0.0 heightSampleCount=3 heightAppliedCount=2 sourceProgressCount=1 applyCount=1 domCommitCount=1 totalStreamingDurationMs=300 firstSuccessfulRenderAtMs=100
''';

      final result = analyzer.analyze(
        log,
        logPath: 'sample-spike.log',
      );

      final flow = result.selectedFlow!;
      final primary = flow.primaryAttempt!;

      expect(
        primary.derivedSignals,
        containsAll(<String>[
          'sample_height_spike_then_rollback',
          'artifact_rect_stretch_sampled',
        ]),
      );
      expect(
        flow.summarySignals,
        containsAll(<String>[
          'sample_spike_rollback',
          'artifact_rect_stretch',
        ]),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt sampled a short-lived height spike before rollback (180px -> 220px -> 180px).',
        ),
      );
    });

    test(
        'detects a runtime sampled content collapse before apply when host height stays larger than content',
        () {
      const log = '''
2026-06-08T01:02:14.000000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-runtime-collapse flowId=turn_5:artifact_5:call_5 reason=diagnose create_artifact render session turnId=turn_5 artifactId=artifact_5 providerCallId=call_5 sourcePath=runtime://create_artifact/call_5 phase=runtime isRuntimePreview=true
2026-06-08T01:02:14.726807+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-collapse flowId=turn_5:artifact_5:call_5 reason=diagnose create_artifact render session phase=runtime seq=3 appliedHeight=263.0 maxAppliedHeight=263.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T01:02:23.458574+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-runtime-collapse flowId=turn_5:artifact_5:call_5 reason=diagnose create_artifact render session phase=runtime seq=43 rawHeight=114.0 clampedHeight=180.0 heightBasis=artifactRect artifactRectHeight=113.36038208007812 artifactOffsetHeight=113.0 artifactScrollHeight=113.0 artifactClientHeight=113.0 bodyScrollHeight=113.0 bodyOffsetHeight=113.0 bodyClientHeight=113.0 rootScrollHeight=263.0 rootOffsetHeight=113.0 rootClientHeight=263.0 previousAppliedHeight=263.0 sampleDeltaFromPreviousAppliedPx=-149.0 sampledFromPendingFinalController=false hasPendingFinalController=false hostViewportProbeStatus=ok controllerSourcePathMismatch=false rootScrollOutlierPx=0.0 artifactRectStretchPx=0.360382080078125 hostViewportRenderHeight=320.0 hostViewportConfiguredHeight=263.0 hostViewportOvershootPx=57.0 hostViewportGapFromMeasuredHeightPx=206.0 hostViewportGapFromClampedHeightPx=140.0
2026-06-08T01:02:23.707131+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-collapse flowId=turn_5:artifact_5:call_5 reason=diagnose create_artifact render session phase=runtime seq=4 appliedHeight=180.0 maxAppliedHeight=263.0 largestDropPx=83.0 isPreviewTruncated=false
2026-06-08T01:02:23.866660+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-collapse flowId=turn_5:artifact_5:call_5 reason=diagnose create_artifact render session phase=runtime seq=5 appliedHeight=180.0 maxAppliedHeight=263.0 largestDropPx=83.0 isPreviewTruncated=false
2026-06-08T01:02:24.000000+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-runtime-collapse flowId=turn_5:artifact_5:call_5 verdict=anomalous anomalyCodes=[artifact_height_drop_over_30px] phaseSummary=runtime artifactId=artifact_5 providerCallId=call_5 sourcePath=runtime://create_artifact/call_5 heightPattern=overshootThenDrop maxAppliedHeight=263.0 finalAppliedHeight=180.0 largestDropPx=83.0 heightSampleCount=1 heightAppliedCount=3 sourceProgressCount=1 applyCount=1 domCommitCount=1 totalStreamingDurationMs=10000 firstSuccessfulRenderAtMs=1200
''';

      final result = analyzer.analyze(
        log,
        logPath: 'sampled-collapse.log',
      );

      final flow = result.selectedFlow!;
      final primary = flow.primaryAttempt!;

      expect(
        primary.derivedSignals,
        containsAll(<String>[
          'sampled_content_collapse_before_apply',
          'viewport_content_gap_sampled',
          'root_viewport_content_gap_sampled',
          'height_clamp_lift_sampled',
          'host_viewport_measured_gap_sampled',
          'host_viewport_overshoot_sampled',
        ]),
      );
      expect(primary.sampledCollapseFromHeight, 263.0);
      expect(primary.sampledCollapseToHeight, 180.0);
      expect(primary.sampledCollapseRawHeight, 114.0);
      expect(primary.sampledCollapseDeltaPx, 83.0);
      expect(primary.sampledCollapseHostViewportProbeStatus, 'ok');
      expect(primary.largestViewportContentGapPx, 149.0);
      expect(primary.largestRootViewportContentGapPx, 149.0);
      expect(primary.largestClampLiftPx, 66.0);
      expect(primary.largestHostViewportMeasuredGapPx, 206.0);
      expect(primary.largestHostViewportClampedGapPx, 140.0);
      expect(primary.largestHostViewportOvershootPx, 57.0);
      expect(primary.hostViewportProbeStatusCounts, <String, int>{'ok': 1});
      expect(
        flow.summarySignals,
        containsAll(<String>[
          'sampled_content_collapse',
          'viewport_content_gap',
          'root_viewport_gap',
          'clamp_lift',
          'host_viewport_gap',
          'host_viewport_overshoot',
        ]),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt sampled a content collapse before apply (263px -> 114px raw, 180px clamped).',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt saw host viewport exceed intrinsic content by 149px during sampling.',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt saw root viewport exceed intrinsic content by 149px during sampling.',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt lifted sampled height by 66px via preview height clamp.',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt saw host render viewport exceed intrinsic content by 206px during sampling.',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt saw host render viewport exceed configured preview height by 57px during sampling.',
        ),
      );
    });

    test('surfaces when the host viewport probe never resolves at collapse time',
        () {
      const log = '''
2026-06-08T01:12:14.000000+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-runtime-no-probe flowId=turn_6:artifact_6:call_6 reason=diagnose create_artifact render session turnId=turn_6 artifactId=artifact_6 providerCallId=call_6 sourcePath=runtime://create_artifact/call_6 phase=runtime isRuntimePreview=true
2026-06-08T01:12:14.726807+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-no-probe flowId=turn_6:artifact_6:call_6 reason=diagnose create_artifact render session phase=runtime seq=3 appliedHeight=261.0 maxAppliedHeight=261.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T01:12:23.458574+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-runtime-no-probe flowId=turn_6:artifact_6:call_6 reason=diagnose create_artifact render session phase=runtime seq=43 rawHeight=116.0 clampedHeight=180.0 heightBasis=artifactRect artifactRectHeight=115.1 artifactOffsetHeight=115.0 artifactScrollHeight=115.0 artifactClientHeight=115.0 bodyScrollHeight=116.0 bodyOffsetHeight=116.0 bodyClientHeight=116.0 rootScrollHeight=261.0 rootOffsetHeight=116.0 rootClientHeight=262.0 previousAppliedHeight=261.0 sampleDeltaFromPreviousAppliedPx=-145.0 sampledFromPendingFinalController=false hasPendingFinalController=false hostViewportProbeStatus=no_size controllerSourcePathMismatch=false rootScrollOutlierPx=0.0 artifactRectStretchPx=0.1
2026-06-08T01:12:23.707131+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-no-probe flowId=turn_6:artifact_6:call_6 reason=diagnose create_artifact render session phase=runtime seq=4 appliedHeight=180.0 maxAppliedHeight=261.0 largestDropPx=81.0 isPreviewTruncated=false
2026-06-08T01:12:24.000000+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-runtime-no-probe flowId=turn_6:artifact_6:call_6 verdict=anomalous anomalyCodes=[artifact_height_drop_over_30px] phaseSummary=runtime artifactId=artifact_6 providerCallId=call_6 sourcePath=runtime://create_artifact/call_6 heightPattern=overshootThenDrop maxAppliedHeight=261.0 finalAppliedHeight=180.0 largestDropPx=81.0 heightSampleCount=1 heightAppliedCount=2 sourceProgressCount=1 applyCount=1 domCommitCount=1 totalStreamingDurationMs=10000 firstSuccessfulRenderAtMs=1200
''';

      final result = analyzer.analyze(
        log,
        logPath: 'sampled-collapse-no-probe.log',
      );

      final flow = result.selectedFlow!;
      final primary = flow.primaryAttempt!;

      expect(
        primary.derivedSignals,
        contains('host_viewport_probe_never_resolved'),
      );
      expect(primary.sampledCollapseHostViewportProbeStatus, 'no_size');
      expect(primary.hostViewportProbeStatusCounts, <String, int>{
        'no_size': 1,
      });
      expect(flow.summarySignals, contains('host_viewport_probe_missing'));
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt could not resolve the host viewport probe at the collapse sample (status=no_size).',
        ),
      );
      expect(
        flow.incidentReport.findings,
        contains(
          'Primary attempt never resolved the host viewport probe during sampling (no_size=1).',
        ),
      );
    });

    test('prefers the main runtime incident flow over a later clean final flow',
        () {
      const log = '''
2026-06-08T01:13:33.527787+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-runtime-main flowId=turn_7:artifact_runtime:call_7 reason=diagnose create_artifact render session turnId=turn_7 artifactId=artifact_runtime providerCallId=call_7 sourcePath=runtime://create_artifact/call_7 phase=runtime isRuntimePreview=true
2026-06-08T01:13:34.527787+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-main flowId=turn_7:artifact_runtime:call_7 reason=diagnose create_artifact render session phase=runtime seq=1 appliedHeight=261.0 maxAppliedHeight=261.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T01:13:35.527787+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_sampled sessionId=session-runtime-main flowId=turn_7:artifact_runtime:call_7 reason=diagnose create_artifact render session phase=runtime seq=2 rawHeight=116.0 clampedHeight=180.0 previousAppliedHeight=261.0 sampleDeltaFromPreviousAppliedPx=-145.0 hostViewportProbeStatus=no_size rootClientHeight=262.0 artifactRectStretchPx=0.0
2026-06-08T01:13:36.527787+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-runtime-main flowId=turn_7:artifact_runtime:call_7 reason=diagnose create_artifact render session phase=runtime seq=2 appliedHeight=180.0 maxAppliedHeight=261.0 largestDropPx=81.0 isPreviewTruncated=false
2026-06-08T01:13:54.270573+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-runtime-main flowId=turn_7:artifact_runtime:call_7 verdict=anomalous anomalyCodes=[artifact_height_drop_over_30px] phaseSummary=runtime artifactId=artifact_runtime providerCallId=call_7 sourcePath=runtime://create_artifact/call_7 heightPattern=sawtooth maxAppliedHeight=746.0 finalAppliedHeight=746.0 largestDropPx=81.0 heightSampleCount=1 heightAppliedCount=2 sourceProgressCount=10 applyCount=3 domCommitCount=3 totalStreamingDurationMs=20742 firstSuccessfulRenderAtMs=1249
2026-06-08T01:13:54.290215+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-final-clean flowId=turn_7:artifact_final:call_7 reason=diagnose create_artifact render session turnId=turn_7 artifactId=artifact_final providerCallId=call_7 sourcePath=/workspaces/ws/artifacts/final.html phase=finalTakeover isRuntimePreview=false
2026-06-08T01:13:54.693765+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.height_applied sessionId=session-final-clean flowId=turn_7:artifact_final:call_7 reason=diagnose create_artifact render session phase=finalTakeover seq=1 appliedHeight=746.0 maxAppliedHeight=746.0 largestDropPx=0.0 isPreviewTruncated=false
2026-06-08T01:13:54.913780+08:00 INFO [trace] [ArtifactRenderSessionRecorder] artifact.preview.session_done sessionId=session-final-clean flowId=turn_7:artifact_final:call_7 verdict=normal anomalyCodes=[] phaseSummary=finalTakeover artifactId=artifact_final providerCallId=call_7 sourcePath=/workspaces/ws/artifacts/final.html heightPattern=monotonicGrowth maxAppliedHeight=746.0 finalAppliedHeight=746.0 largestDropPx=0.0 heightSampleCount=0 heightAppliedCount=1 sourceProgressCount=1 applyCount=0 domCommitCount=0 totalStreamingDurationMs=623
''';

      final result = analyzer.analyze(
        log,
        logPath: 'default-flow-selection.log',
      );

      expect(result.selectedFlow, isNotNull);
      expect(result.selectedFlow!.flowId, 'turn_7:artifact_runtime:call_7');
      expect(result.selectedFlow!.primaryAttempt!.phaseSummary, 'runtime');
    });

    test('returns null selected flow when the requested flow id is absent', () {
      const log = '''
2026-06-06T03:04:07.001652+08:00 DEBUG [temp] [ArtifactRenderSessionRecorder] artifact.preview.session_started sessionId=session-1 flowId=turn_1:artifact_1:call_1 reason=diagnose create_artifact render session turnId=turn_1 artifactId=artifact_1 providerCallId=call_1 sourcePath=runtime://create_artifact/call_1 phase=runtime isRuntimePreview=true
''';

      final result = analyzer.analyze(
        log,
        selectedFlowId: 'missing-flow',
      );

      expect(result.flows, hasLength(1));
      expect(result.selectedFlow, isNull);
    });
  });
}
