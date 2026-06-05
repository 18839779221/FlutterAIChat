import 'package:ai_chat/models/artifact/artifact_render_session_snapshot.dart';
import 'package:ai_chat/utils/logger.dart';

const String artifactHeightDropOver30pxDiagnosticCode =
    'artifact_height_drop_over_30px';
const String artifactFirstRenderInFinalSecondDiagnosticCode =
    'artifact_first_render_in_final_second';

typedef ArtifactRenderTraceEmitter = void Function(
  String tag,
  String message, {
  LogLevel level,
  Map<String, dynamic>? data,
});

typedef ArtifactRenderTempEmitter = void Function(
  String tag,
  String message, {
  LogLevel level,
  String? reason,
  Map<String, dynamic>? data,
});

/// Aggregates runtime-only observability for one inline artifact render flow.
class ArtifactRenderSessionRecorder {
  ArtifactRenderSessionRecorder({
    ArtifactRenderTraceEmitter? traceEmitter,
    ArtifactRenderTempEmitter? tempEmitter,
  })  : _traceEmitter = traceEmitter ?? Logger.trace,
        _tempEmitter = tempEmitter ?? Logger.temp;

  final ArtifactRenderTraceEmitter _traceEmitter;
  final ArtifactRenderTempEmitter _tempEmitter;
  final Map<String, _ActiveArtifactRenderSession> _sessions =
      <String, _ActiveArtifactRenderSession>{};

  void startSession({
    required String sessionId,
    required String turnId,
    required String artifactId,
    String? providerCallId,
    required String sourcePath,
    required ArtifactRenderPhase phase,
    required bool isRuntimePreview,
    required DateTime timestamp,
  }) {
    _sessions[sessionId] = _ActiveArtifactRenderSession(
      sessionId: sessionId,
      turnId: turnId,
      artifactId: artifactId,
      providerCallId: providerCallId,
      sourcePath: sourcePath,
      startedAt: timestamp,
      currentPhase: phase,
      isRuntimePreview: isRuntimePreview,
    );
    _emitSessionEvent(
      'artifact.preview.session_started',
      sessionId: sessionId,
      data: {
        'turnId': turnId,
        'artifactId': artifactId,
        'providerCallId': providerCallId,
        'sourcePath': sourcePath,
        'phase': phase.name,
        'isRuntimePreview': isRuntimePreview,
      },
    );
  }

  void recordSourceProgressed({
    required String sessionId,
    required int sourceLength,
    required int deltaLength,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.sourceProgressCount += 1;
    session.lastSourceLength = sourceLength;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.source_progressed',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'seq': session.sourceProgressCount,
        'sourceLength': sourceLength,
        'deltaLength': deltaLength,
      },
    );
  }

  void recordRuntimeApplyStarted({
    required String sessionId,
    required int sourceLength,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.applyCount += 1;
    session.lastSourceLength = sourceLength;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.runtime_apply_started',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'seq': session.applyCount,
        'sourceLength': sourceLength,
      },
    );
  }

  void recordRuntimeApplyCompleted({
    required String sessionId,
    required int sourceLength,
    required String result,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.runtimeApplyCompletedAt ??= timestamp;
    session.lastSourceLength = sourceLength;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.runtime_apply_completed',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'seq': session.applyCount,
        'sourceLength': sourceLength,
        'result': result,
      },
    );
  }

  void recordDomCommit({
    required String sessionId,
    required int sourceLength,
    required double? artifactRectHeight,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.domCommitCount += 1;
    session.firstDomCommitAt ??= timestamp;
    session.lastSourceLength = sourceLength;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.dom_commit',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'seq': session.domCommitCount,
        'sourceLength': sourceLength,
        'artifactRectHeight': artifactRectHeight,
      },
    );
  }

  void recordHeightSampled({
    required String sessionId,
    required double rawHeight,
    required double clampedHeight,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.heightSampleCount += 1;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.height_sampled',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'seq': session.heightSampleCount,
        'rawHeight': rawHeight,
        'clampedHeight': clampedHeight,
      },
    );
  }

  void recordHeightApplied({
    required String sessionId,
    required double appliedHeight,
    required bool isPreviewTruncated,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }

    session.heightAppliedCount += 1;
    session.lastUpdatedAt = timestamp;
    session.finalAppliedHeight = appliedHeight;
    session.firstHeightAppliedAt ??= timestamp;

    final previousHeight = session.lastAppliedHeight;
    if (previousHeight != null) {
      if (appliedHeight < previousHeight) {
        session.decreaseCount += 1;
      } else if (appliedHeight > previousHeight) {
        session.increaseCount += 1;
      }
    }

    final maxSeen = session.maxAppliedHeight;
    if (maxSeen == null || appliedHeight > maxSeen) {
      session.maxAppliedHeight = appliedHeight;
    } else {
      final dropPx = maxSeen - appliedHeight;
      if (dropPx > session.largestDropPx) {
        session.largestDropPx = dropPx;
      }
      if (dropPx > 30 &&
          !session.anomalyCodes.contains(
            artifactHeightDropOver30pxDiagnosticCode,
          )) {
        session.anomalyCodes.add(artifactHeightDropOver30pxDiagnosticCode);
        _traceEmitter(
          'ArtifactRenderSessionRecorder',
          'artifact.preview.anomaly',
          data: {
            'sessionId': session.sessionId,
            'diagnosticCode': artifactHeightDropOver30pxDiagnosticCode,
            'phase': session.currentPhase.name,
            'artifactId': session.artifactId,
            'providerCallId': session.providerCallId,
            'sourcePath': session.sourcePath,
            'details': <String, dynamic>{
              'maxAppliedHeight': maxSeen,
              'currentAppliedHeight': appliedHeight,
              'largestDropPx': session.largestDropPx,
              'previousAppliedHeight': previousHeight,
              'sourceLength': session.lastSourceLength,
              'hasPendingFinalController': session.finalTakeoverAt == null,
            },
          },
        );
      }
    }

    session.lastAppliedHeight = appliedHeight;
    _maybeSetFirstSuccessfulRender(session, timestamp);
    _emitSessionEvent(
      'artifact.preview.height_applied',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'seq': session.heightAppliedCount,
        'appliedHeight': appliedHeight,
        'maxAppliedHeight': session.maxAppliedHeight,
        'largestDropPx': session.largestDropPx,
        'isPreviewTruncated': isPreviewTruncated,
      },
    );
  }

  void recordFinalControllerPrepared({
    required String sessionId,
    required int sourceLength,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.currentPhase = ArtifactRenderPhase.finalTakeover;
    session.lastSourceLength = sourceLength;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.final_controller_prepared',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'sourceLength': sourceLength,
      },
    );
  }

  void recordFinalTakeover({
    required String sessionId,
    required int sourceLength,
    required DateTime timestamp,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    session.currentPhase = ArtifactRenderPhase.finalTakeover;
    session.finalTakeoverAt = timestamp;
    session.lastSourceLength = sourceLength;
    session.lastUpdatedAt = timestamp;
    _emitSessionEvent(
      'artifact.preview.final_takeover',
      sessionId: sessionId,
      data: {
        'phase': session.currentPhase.name,
        'sourceLength': sourceLength,
      },
    );
  }

  ArtifactRenderSessionSnapshot finishSession({
    required String sessionId,
    required DateTime timestamp,
  }) {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      throw StateError('Unknown artifact render session: $sessionId');
    }
    session.lastUpdatedAt = timestamp;

    final totalStreamingDurationMs =
        timestamp.difference(session.startedAt).inMilliseconds;
    final firstSuccessfulRenderAt = session.firstSuccessfulRenderAt;
    final firstSuccessfulRenderAtMs = firstSuccessfulRenderAt
        ?.difference(session.startedAt)
        .inMilliseconds;

    if (firstSuccessfulRenderAtMs != null &&
        totalStreamingDurationMs > 3000 &&
        firstSuccessfulRenderAtMs >= totalStreamingDurationMs - 1000 &&
        !session.anomalyCodes.contains(
          artifactFirstRenderInFinalSecondDiagnosticCode,
        )) {
      session.anomalyCodes.add(artifactFirstRenderInFinalSecondDiagnosticCode);
      _traceEmitter(
        'ArtifactRenderSessionRecorder',
        'artifact.preview.anomaly',
        data: {
          'sessionId': session.sessionId,
          'diagnosticCode': artifactFirstRenderInFinalSecondDiagnosticCode,
          'phase': session.currentPhase.name,
          'artifactId': session.artifactId,
          'providerCallId': session.providerCallId,
          'sourcePath': session.sourcePath,
          'details': <String, dynamic>{
            'totalStreamingDurationMs': totalStreamingDurationMs,
            'firstSuccessfulRenderAtMs': firstSuccessfulRenderAtMs,
            'tailWindowMs': totalStreamingDurationMs - firstSuccessfulRenderAtMs,
            'sourceProgressCount': session.sourceProgressCount,
            'applyCount': session.applyCount,
            'domCommitCount': session.domCommitCount,
            'heightAppliedCount': session.heightAppliedCount,
          },
        },
      );
    }

    final snapshot = ArtifactRenderSessionSnapshot(
      sessionId: session.sessionId,
      turnId: session.turnId,
      artifactId: session.artifactId,
      sourcePath: session.sourcePath,
      verdict: session.anomalyCodes.isEmpty
          ? ArtifactRenderSessionVerdict.normal
          : ArtifactRenderSessionVerdict.anomalous,
      anomalyCodes: List.unmodifiable(session.anomalyCodes),
      heightPattern: _classifyHeightPattern(session),
      maxAppliedHeight: session.maxAppliedHeight,
      finalAppliedHeight: session.finalAppliedHeight,
      largestDropPx: session.largestDropPx,
      totalStreamingDurationMs: totalStreamingDurationMs,
      firstSuccessfulRenderAtMs: firstSuccessfulRenderAtMs,
      sourceProgressCount: session.sourceProgressCount,
      applyCount: session.applyCount,
      domCommitCount: session.domCommitCount,
      heightSampleCount: session.heightSampleCount,
      heightAppliedCount: session.heightAppliedCount,
      phaseSummary: session.finalTakeoverAt == null
          ? session.currentPhase.name
          : '${ArtifactRenderPhase.runtime.name}->${ArtifactRenderPhase.finalTakeover.name}',
    );

    _traceEmitter(
      'ArtifactRenderSessionRecorder',
      'artifact.preview.session_done',
      data: {
        'sessionId': snapshot.sessionId,
        'verdict': snapshot.verdict.name,
        'anomalyCodes': snapshot.anomalyCodes,
        'phaseSummary': snapshot.phaseSummary,
        'artifactId': snapshot.artifactId,
        'providerCallId': session.providerCallId,
        'sourcePath': snapshot.sourcePath,
        'heightPattern': snapshot.heightPattern.name,
        'maxAppliedHeight': snapshot.maxAppliedHeight,
        'finalAppliedHeight': snapshot.finalAppliedHeight,
        'largestDropPx': snapshot.largestDropPx,
        'heightSampleCount': snapshot.heightSampleCount,
        'heightAppliedCount': snapshot.heightAppliedCount,
        'sourceProgressCount': snapshot.sourceProgressCount,
        'applyCount': snapshot.applyCount,
        'domCommitCount': snapshot.domCommitCount,
        'totalStreamingDurationMs': snapshot.totalStreamingDurationMs,
        'firstSuccessfulRenderAtMs': snapshot.firstSuccessfulRenderAtMs,
        'timeToFirstSuccessfulRenderMs': snapshot.firstSuccessfulRenderAtMs,
        'tailWindowMs': snapshot.firstSuccessfulRenderAtMs == null
            ? null
            : snapshot.totalStreamingDurationMs -
                snapshot.firstSuccessfulRenderAtMs!,
      },
    );

    return snapshot;
  }

  void _maybeSetFirstSuccessfulRender(
    _ActiveArtifactRenderSession session,
    DateTime timestamp,
  ) {
    if (session.firstSuccessfulRenderAt != null) {
      return;
    }
    if (session.runtimeApplyCompletedAt == null) {
      return;
    }
    if (session.firstDomCommitAt == null) {
      return;
    }
    if (session.heightAppliedCount < 1) {
      return;
    }
    session.firstSuccessfulRenderAt = timestamp;
  }

  ArtifactRenderHeightPattern _classifyHeightPattern(
    _ActiveArtifactRenderSession session,
  ) {
    if (session.heightAppliedCount == 0) {
      return ArtifactRenderHeightPattern.noHeightSignal;
    }
    if (session.finalTakeoverAt != null &&
        session.anomalyCodes.contains(
          artifactHeightDropOver30pxDiagnosticCode,
        )) {
      return ArtifactRenderHeightPattern.finalTakeoverDrop;
    }
    if (session.increaseCount > 1 && session.decreaseCount > 1) {
      return ArtifactRenderHeightPattern.sawtooth;
    }
    if (session.anomalyCodes.contains(
      artifactHeightDropOver30pxDiagnosticCode,
    )) {
      return ArtifactRenderHeightPattern.overshootThenDrop;
    }
    return ArtifactRenderHeightPattern.monotonicGrowth;
  }

  void _emitSessionEvent(
    String message, {
    required String sessionId,
    required Map<String, dynamic> data,
  }) {
    _tempEmitter(
      'ArtifactRenderSessionRecorder',
      message,
      reason: 'diagnose create_artifact render session',
      data: {
        'sessionId': sessionId,
        ...data,
      },
    );
  }
}

class _ActiveArtifactRenderSession {
  _ActiveArtifactRenderSession({
    required this.sessionId,
    required this.turnId,
    required this.artifactId,
    required this.providerCallId,
    required this.sourcePath,
    required this.startedAt,
    required this.currentPhase,
    required this.isRuntimePreview,
  });

  final String sessionId;
  final String turnId;
  final String artifactId;
  final String? providerCallId;
  final String sourcePath;
  final DateTime startedAt;
  final bool isRuntimePreview;

  ArtifactRenderPhase currentPhase;
  DateTime? lastUpdatedAt;
  DateTime? runtimeApplyCompletedAt;
  DateTime? firstDomCommitAt;
  DateTime? firstHeightAppliedAt;
  DateTime? firstSuccessfulRenderAt;
  DateTime? finalTakeoverAt;

  int sourceProgressCount = 0;
  int applyCount = 0;
  int domCommitCount = 0;
  int heightSampleCount = 0;
  int heightAppliedCount = 0;
  int increaseCount = 0;
  int decreaseCount = 0;
  int? lastSourceLength;

  double? lastAppliedHeight;
  double? maxAppliedHeight;
  double? finalAppliedHeight;
  double largestDropPx = 0;

  final List<String> anomalyCodes = <String>[];
}
