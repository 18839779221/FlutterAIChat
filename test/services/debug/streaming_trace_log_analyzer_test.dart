import 'package:ai_chat/services/debug/streaming_trace_log_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingTraceLogAnalyzer', () {
    test('flags long stream that first becomes visible in final second', () {
      const log = '''
2026-06-08T10:00:00.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=turnStarted elapsedMsFromStart=0 userMessagePreview=帮我可视化iOS架构
2026-06-08T10:00:00.100000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=modelRequestStarted elapsedMsFromStart=100 phase=tool_call toolName=create_artifact
2026-06-08T10:00:01.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=modelFirstChunk elapsedMsFromStart=1000 phase=tool_call toolName=create_artifact
2026-06-08T10:00:01.100000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=toolCallStarted elapsedMsFromStart=1100 toolName=create_artifact
2026-06-08T10:00:02.400000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=toolCallCompleted elapsedMsFromStart=2400 toolName=create_artifact
2026-06-08T10:00:02.500000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=modelRequestCompleted elapsedMsFromStart=2500 phase=tool_call toolName=create_artifact
2026-06-08T10:00:02.600000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=modelRequestStarted elapsedMsFromStart=2600 phase=final_answer
2026-06-08T10:00:03.500000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=modelFirstChunk elapsedMsFromStart=3500 phase=final_answer
2026-06-08T10:00:03.500000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=uiFirstVisible elapsedMsFromStart=3500 previewText=已生成可视化
2026-06-08T10:00:04.200000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=modelRequestCompleted elapsedMsFromStart=4200 phase=final_answer
2026-06-08T10:00:04.200000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_96_stream turnId=96 stage=finalTakeover elapsedMsFromStart=4200 previewText=已生成可视化
2026-06-08T10:00:04.200000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.lifecycle traceId=turn_96_stream turnId=96 lifecycleStatus=completed currentStage=finalTakeover entryCount=11 takeoverAt=2026-06-08T10:00:04.200000+08:00
''';

      final analysis = const StreamingTraceLogAnalyzer().analyze(
        log,
        logPath: 'build/artifact-debug/latest.log',
      );

      final selected = analysis.selectedTrace;
      expect(selected, isNotNull);
      expect(selected!.traceId, 'turn_96_stream');
      expect(selected.totalElapsedMs, 4200);
      expect(selected.firstVisibleAtMs, 3500);
      expect(selected.tailWindowMs, 700);
      expect(selected.summarySignals, contains('long_total_stream'));
      expect(
        selected.summarySignals,
        contains('first_visible_in_final_second'),
      );
      expect(
          selected.incidentReport.headline, 'late_visible_after_long_stream');
      expect(selected.finalAnswerSegment, isNotNull);
      expect(selected.finalAnswerSegment!.modelFirstChunkDelayMs, 900);
      expect(selected.finalAnswerSegment!.modelStreamingDurationMs, 700);
    });

    test('falls back to final takeover when uiFirstVisible never arrived', () {
      const log = '''
2026-06-08T11:00:00.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_97_stream turnId=97 stage=turnStarted elapsedMsFromStart=0 userMessagePreview=帮我可视化Android架构
2026-06-08T11:00:00.100000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_97_stream turnId=97 stage=modelRequestStarted elapsedMsFromStart=100 phase=final_answer
2026-06-08T11:00:03.300000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_97_stream turnId=97 stage=modelFirstChunk elapsedMsFromStart=3300 phase=final_answer
2026-06-08T11:00:04.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_97_stream turnId=97 stage=modelRequestCompleted elapsedMsFromStart=4000 phase=final_answer
2026-06-08T11:00:04.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_97_stream turnId=97 stage=finalTakeover elapsedMsFromStart=4000 previewText=最终一次性出现
2026-06-08T11:00:04.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.lifecycle traceId=turn_97_stream turnId=97 lifecycleStatus=completed currentStage=finalTakeover entryCount=5 takeoverAt=2026-06-08T11:00:04.000000+08:00
''';

      final analysis = const StreamingTraceLogAnalyzer().analyze(log);
      final selected = analysis.selectedTrace;

      expect(selected, isNotNull);
      expect(selected!.firstVisibleAtMs, isNull);
      expect(selected.effectiveFirstVisibleAtMs, 4000);
      expect(selected.summarySignals, contains('visible_only_at_takeover'));
      expect(
        selected.summarySignals,
        contains('first_visible_in_final_second'),
      );
    });

    test('distinguishes artifact preview visibility from final text visibility',
        () {
      const log = '''
2026-06-08T12:00:00.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_98_stream turnId=98 stage=turnStarted elapsedMsFromStart=0
2026-06-08T12:00:01.800000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_98_stream turnId=98 stage=uiFirstVisible elapsedMsFromStart=1800 source=artifact_runtime_preview artifactId=ios-architecture sourcePath=runtime://create_artifact/call_1 sourceLength=512
2026-06-08T12:00:21.400000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_98_stream turnId=98 stage=uiFirstVisible elapsedMsFromStart=21400 source=final_response_text textLength=12 previewText=已生成可视化
2026-06-08T12:00:22.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.stage traceId=turn_98_stream turnId=98 stage=finalTakeover elapsedMsFromStart=22000 previewText=最终回答
2026-06-08T12:00:22.000000+08:00 INFO [trace] [StreamingTraceRecorder] streaming.trace.lifecycle traceId=turn_98_stream turnId=98 lifecycleStatus=completed currentStage=finalTakeover entryCount=4 takeoverAt=2026-06-08T12:00:22.000000+08:00
''';

      final analysis = const StreamingTraceLogAnalyzer().analyze(log);
      final selected = analysis.selectedTrace;

      expect(selected, isNotNull);
      expect(selected!.firstVisibleAtMs, 1800);
      expect(selected.firstVisibleSource, 'artifact_runtime_preview');
      expect(selected.artifactFirstVisibleAtMs, 1800);
      expect(selected.finalResponseFirstVisibleAtMs, 21400);
      expect(
        selected.summarySignals,
        contains('final_text_visible_in_final_second'),
      );
      expect(
        selected.incidentReport.findings,
        contains(
          'Artifact preview became visible at 1800ms before final response text.',
        ),
      );
      expect(
        selected.incidentReport.findings,
        contains(
          'Final response text first became visible at 21400ms, leaving only 600ms before completion.',
        ),
      );
    });
  });
}
