class ArtifactRenderLogAnalysis {
  const ArtifactRenderLogAnalysis({
    required this.logPath,
    required this.flows,
    required this.selectedFlow,
  });

  /// Source log path shown in summaries and CLI output.
  final String logPath;

  /// All discovered render flows sorted by latest activity first.
  final List<ArtifactRenderFlowAnalysis> flows;

  /// Flow selected for the current report. Defaults to the latest flow.
  final ArtifactRenderFlowAnalysis? selectedFlow;

  Map<String, dynamic> toJson() {
    return {
      'logPath': logPath,
      'selectedFlowId': selectedFlow?.flowId,
      'flows': flows.map((flow) => flow.toJson()).toList(growable: false),
    };
  }
}

class ArtifactRenderFlowAnalysis {
  const ArtifactRenderFlowAnalysis({
    required this.flowId,
    required this.usedDerivedFlowId,
    required this.turnId,
    required this.artifactId,
    required this.providerCallId,
    required this.firstEventAt,
    required this.lastEventAt,
    required this.renderAttemptCount,
    required this.uniqueSessionIdCount,
    required this.sessionStartCount,
    required this.sessionDoneCount,
    required this.anomalyCodes,
    required this.remountEvidence,
    required this.summarySignals,
    required this.summaryLabel,
    required this.incidentReport,
    required this.primaryAttempt,
    required this.attempts,
  });

  final String flowId;
  final bool usedDerivedFlowId;
  final String? turnId;
  final String? artifactId;
  final String? providerCallId;
  final DateTime firstEventAt;
  final DateTime lastEventAt;
  final int renderAttemptCount;
  final int uniqueSessionIdCount;
  final int sessionStartCount;
  final int sessionDoneCount;
  final List<String> anomalyCodes;
  final List<String> remountEvidence;
  final List<String> summarySignals;
  final String summaryLabel;
  final ArtifactRenderIncidentReport incidentReport;
  final ArtifactRenderAttemptAnalysis? primaryAttempt;
  final List<ArtifactRenderAttemptAnalysis> attempts;

  Map<String, dynamic> toJson() {
    return {
      'flowId': flowId,
      'usedDerivedFlowId': usedDerivedFlowId,
      'turnId': turnId,
      'artifactId': artifactId,
      'providerCallId': providerCallId,
      'firstEventAt': firstEventAt.toIso8601String(),
      'lastEventAt': lastEventAt.toIso8601String(),
      'renderAttemptCount': renderAttemptCount,
      'uniqueSessionIdCount': uniqueSessionIdCount,
      'sessionStartCount': sessionStartCount,
      'sessionDoneCount': sessionDoneCount,
      'anomalyCodes': anomalyCodes,
      'remountEvidence': remountEvidence,
      'summarySignals': summarySignals,
      'summaryLabel': summaryLabel,
      'incidentReport': incidentReport.toJson(),
      'primaryAttempt': primaryAttempt?.toJson(),
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(
            growable: false,
          ),
    };
  }
}

class ArtifactRenderIncidentReport {
  const ArtifactRenderIncidentReport({
    required this.headline,
    required this.findings,
  });

  final String headline;
  final List<String> findings;

  Map<String, dynamic> toJson() {
    return {
      'headline': headline,
      'findings': findings,
    };
  }
}

class ArtifactRenderAttemptAnalysis {
  const ArtifactRenderAttemptAnalysis({
    required this.attemptIndex,
    required this.sessionId,
    required this.startedAt,
    required this.lastEventAt,
    required this.doneAt,
    required this.phase,
    required this.phaseSummary,
    required this.verdict,
    required this.heightPattern,
    required this.sourcePath,
    required this.supersededByRemount,
    required this.anomalyCodes,
    required this.sourceProgressCount,
    required this.applyCount,
    required this.domCommitCount,
    required this.heightAppliedCount,
    required this.heightSampleCount,
    required this.totalStreamingDurationMs,
    required this.firstSuccessfulRenderAtMs,
    required this.tailWindowMs,
    required this.maxAppliedHeight,
    required this.finalAppliedHeight,
    required this.largestDropPx,
    required this.largestRecoveryPx,
    required this.pendingFinalInjectionFromHeight,
    required this.pendingFinalInjectionToHeight,
    required this.pendingFinalInjectionDeltaPx,
    required this.largestRootScrollOutlierPx,
    required this.largestArtifactRectStretchPx,
    required this.sampleSpikeFromHeight,
    required this.sampleSpikePeakHeight,
    required this.sampleSpikeRollbackHeight,
    required this.sampleSpikeDeltaPx,
    required this.sampledCollapseFromHeight,
    required this.sampledCollapseToHeight,
    required this.sampledCollapseRawHeight,
    required this.sampledCollapseDeltaPx,
    required this.sampledCollapseHostViewportProbeStatus,
    required this.largestViewportContentGapPx,
    required this.largestRootViewportContentGapPx,
    required this.largestClampLiftPx,
    required this.largestHostViewportMeasuredGapPx,
    required this.largestHostViewportClampedGapPx,
    required this.largestHostViewportOvershootPx,
    required this.hostViewportProbeStatusCounts,
    required this.derivedSignals,
  });

  final int attemptIndex;
  final String sessionId;
  final DateTime? startedAt;
  final DateTime lastEventAt;
  final DateTime? doneAt;
  final String? phase;
  final String? phaseSummary;
  final String? verdict;
  final String? heightPattern;
  final String? sourcePath;
  final bool supersededByRemount;
  final List<String> anomalyCodes;
  final int sourceProgressCount;
  final int applyCount;
  final int domCommitCount;
  final int heightAppliedCount;
  final int heightSampleCount;
  final int? totalStreamingDurationMs;
  final int? firstSuccessfulRenderAtMs;
  final int? tailWindowMs;
  final double? maxAppliedHeight;
  final double? finalAppliedHeight;
  final double? largestDropPx;
  final double? largestRecoveryPx;
  final double? pendingFinalInjectionFromHeight;
  final double? pendingFinalInjectionToHeight;
  final double? pendingFinalInjectionDeltaPx;
  final double? largestRootScrollOutlierPx;
  final double? largestArtifactRectStretchPx;
  final double? sampleSpikeFromHeight;
  final double? sampleSpikePeakHeight;
  final double? sampleSpikeRollbackHeight;
  final double? sampleSpikeDeltaPx;
  final double? sampledCollapseFromHeight;
  final double? sampledCollapseToHeight;
  final double? sampledCollapseRawHeight;
  final double? sampledCollapseDeltaPx;
  final String? sampledCollapseHostViewportProbeStatus;
  final double? largestViewportContentGapPx;
  final double? largestRootViewportContentGapPx;
  final double? largestClampLiftPx;
  final double? largestHostViewportMeasuredGapPx;
  final double? largestHostViewportClampedGapPx;
  final double? largestHostViewportOvershootPx;
  final Map<String, int> hostViewportProbeStatusCounts;
  final List<String> derivedSignals;

  bool get hasRenderSignal =>
      domCommitCount > 0 || heightAppliedCount > 0 || applyCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'attemptIndex': attemptIndex,
      'sessionId': sessionId,
      'startedAt': startedAt?.toIso8601String(),
      'lastEventAt': lastEventAt.toIso8601String(),
      'doneAt': doneAt?.toIso8601String(),
      'phase': phase,
      'phaseSummary': phaseSummary,
      'verdict': verdict,
      'heightPattern': heightPattern,
      'sourcePath': sourcePath,
      'supersededByRemount': supersededByRemount,
      'anomalyCodes': anomalyCodes,
      'sourceProgressCount': sourceProgressCount,
      'applyCount': applyCount,
      'domCommitCount': domCommitCount,
      'heightAppliedCount': heightAppliedCount,
      'heightSampleCount': heightSampleCount,
      'totalStreamingDurationMs': totalStreamingDurationMs,
      'firstSuccessfulRenderAtMs': firstSuccessfulRenderAtMs,
      'tailWindowMs': tailWindowMs,
      'maxAppliedHeight': maxAppliedHeight,
      'finalAppliedHeight': finalAppliedHeight,
      'largestDropPx': largestDropPx,
      'largestRecoveryPx': largestRecoveryPx,
      'pendingFinalInjectionFromHeight': pendingFinalInjectionFromHeight,
      'pendingFinalInjectionToHeight': pendingFinalInjectionToHeight,
      'pendingFinalInjectionDeltaPx': pendingFinalInjectionDeltaPx,
      'largestRootScrollOutlierPx': largestRootScrollOutlierPx,
      'largestArtifactRectStretchPx': largestArtifactRectStretchPx,
      'sampleSpikeFromHeight': sampleSpikeFromHeight,
      'sampleSpikePeakHeight': sampleSpikePeakHeight,
      'sampleSpikeRollbackHeight': sampleSpikeRollbackHeight,
      'sampleSpikeDeltaPx': sampleSpikeDeltaPx,
      'sampledCollapseFromHeight': sampledCollapseFromHeight,
      'sampledCollapseToHeight': sampledCollapseToHeight,
      'sampledCollapseRawHeight': sampledCollapseRawHeight,
      'sampledCollapseDeltaPx': sampledCollapseDeltaPx,
      'sampledCollapseHostViewportProbeStatus':
          sampledCollapseHostViewportProbeStatus,
      'largestViewportContentGapPx': largestViewportContentGapPx,
      'largestRootViewportContentGapPx': largestRootViewportContentGapPx,
      'largestClampLiftPx': largestClampLiftPx,
      'largestHostViewportMeasuredGapPx': largestHostViewportMeasuredGapPx,
      'largestHostViewportClampedGapPx': largestHostViewportClampedGapPx,
      'largestHostViewportOvershootPx': largestHostViewportOvershootPx,
      'hostViewportProbeStatusCounts': hostViewportProbeStatusCounts,
      'derivedSignals': derivedSignals,
    };
  }
}

/// Parses app.log lines emitted by `ArtifactRenderSessionRecorder` and
/// reconstructs a flow-level report centered on one logical create_artifact run.
class ArtifactRenderLogAnalyzer {
  const ArtifactRenderLogAnalyzer();

  ArtifactRenderLogAnalysis analyze(
    String content, {
    String logPath = '<memory>',
    String? selectedFlowId,
  }) {
    final builders = <String, _FlowBuilder>{};
    final sessionFlowIds = <String, String>{};

    for (final rawLine in content.split('\n')) {
      final entry = _ArtifactLogEntry.tryParse(rawLine);
      if (entry == null) {
        continue;
      }

      final explicitFlowId = _readString(entry.fields, 'flowId');
      final sessionMappedFlowId =
          entry.sessionId == null ? null : sessionFlowIds[entry.sessionId!];
      final derivedFlowId =
          _deriveFlowId(entry.fields, sessionId: entry.sessionId);
      final resolvedFlowId =
          explicitFlowId ?? sessionMappedFlowId ?? derivedFlowId;
      if (resolvedFlowId == null) {
        continue;
      }

      final builder = builders.putIfAbsent(
        resolvedFlowId,
        () => _FlowBuilder(
          flowId: resolvedFlowId,
          usedDerivedFlowId: explicitFlowId == null,
        ),
      );
      builder.usedDerivedFlowId =
          builder.usedDerivedFlowId && explicitFlowId == null;
      builder.registerEntry(entry);

      if (entry.sessionId != null) {
        sessionFlowIds[entry.sessionId!] = resolvedFlowId;
      }

      switch (entry.message) {
        case 'artifact.preview.session_started':
          builder.handleSessionStarted(entry);
          break;
        case 'artifact.preview.source_progressed':
          builder.handleSourceProgressed(entry);
          break;
        case 'artifact.preview.runtime_apply_started':
          builder.handleRuntimeApplyStarted(entry);
          break;
        case 'artifact.preview.runtime_apply_completed':
          builder.handleRuntimeApplyCompleted(entry);
          break;
        case 'artifact.preview.dom_commit':
          builder.handleDomCommit(entry);
          break;
        case 'artifact.preview.height_sampled':
          builder.handleHeightSampled(entry);
          break;
        case 'artifact.preview.height_applied':
          builder.handleHeightApplied(entry);
          break;
        case 'artifact.preview.final_controller_prepared':
          builder.handlePhaseEvent(entry);
          break;
        case 'artifact.preview.final_takeover':
          builder.handlePhaseEvent(entry);
          break;
        case 'artifact.preview.anomaly':
          builder.handleAnomaly(entry);
          break;
        case 'artifact.preview.session_done':
          builder.handleSessionDone(entry);
          break;
      }
    }

    final flows = builders.values
        .map((builder) => builder.build())
        .whereType<ArtifactRenderFlowAnalysis>()
        .toList(growable: false)
      ..sort((a, b) => b.lastEventAt.compareTo(a.lastEventAt));

    final selectedFlow = selectedFlowId != null
        ? flows.where((flow) => flow.flowId == selectedFlowId).firstOrNull
        : _selectDefaultFlow(flows);

    return ArtifactRenderLogAnalysis(
      logPath: logPath,
      flows: flows,
      selectedFlow: selectedFlow,
    );
  }

  ArtifactRenderFlowAnalysis? _selectDefaultFlow(
    List<ArtifactRenderFlowAnalysis> flows,
  ) {
    if (flows.isEmpty) {
      return null;
    }
    final ranked = flows.toList(growable: false)
      ..sort((a, b) {
        final scoreCompare =
            _defaultFlowScore(b).compareTo(_defaultFlowScore(a));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return b.lastEventAt.compareTo(a.lastEventAt);
      });
    return ranked.first;
  }

  int _defaultFlowScore(ArtifactRenderFlowAnalysis flow) {
    final primary = flow.primaryAttempt;
    final phase = primary?.phaseSummary ?? primary?.phase;
    final anomalyBoost = flow.anomalyCodes.isNotEmpty ? 100000000 : 0;
    final signalBoost = flow.summarySignals.isNotEmpty ? 10000000 : 0;
    final runtimeBoost = phase == 'runtime' ? 1000000 : 0;
    final renderBoost = primary?.hasRenderSignal == true ? 100000 : 0;
    final durationBoost = primary?.totalStreamingDurationMs ?? 0;
    final dropBoost = (((primary?.largestDropPx ?? 0.0) * 100).round());
    return anomalyBoost +
        signalBoost +
        runtimeBoost +
        renderBoost +
        durationBoost +
        dropBoost;
  }

  String? _deriveFlowId(
    Map<String, String> fields, {
    String? sessionId,
  }) {
    final turnId = _readString(fields, 'turnId');
    final artifactId = _readString(fields, 'artifactId');
    final providerCallId = _readString(fields, 'providerCallId');
    if (turnId != null && artifactId != null && providerCallId != null) {
      return '$turnId:$artifactId:$providerCallId';
    }
    if (turnId != null && artifactId != null) {
      return '$turnId:$artifactId';
    }
    if (artifactId != null && providerCallId != null) {
      return 'derived:$artifactId:$providerCallId';
    }
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      return 'derived:$sessionId';
    }
    return null;
  }
}

class _FlowBuilder {
  _FlowBuilder({
    required this.flowId,
    required this.usedDerivedFlowId,
  });

  final String flowId;
  bool usedDerivedFlowId;

  String? turnId;
  String? artifactId;
  String? providerCallId;
  DateTime? firstEventAt;
  DateTime? lastEventAt;
  int sessionStartCount = 0;
  int sessionDoneCount = 0;

  final List<_AttemptBuilder> _attempts = <_AttemptBuilder>[];
  final Map<String, _AttemptBuilder> _activeAttemptsBySessionId =
      <String, _AttemptBuilder>{};
  final Map<String, _AttemptBuilder> _lastAttemptsBySessionId =
      <String, _AttemptBuilder>{};
  final Set<String> _flowAnomalyCodes = <String>{};

  void registerEntry(_ArtifactLogEntry entry) {
    firstEventAt ??= entry.timestamp;
    lastEventAt = entry.timestamp;
    turnId ??= _readString(entry.fields, 'turnId');
    artifactId ??= _readString(entry.fields, 'artifactId');
    providerCallId ??= _readString(entry.fields, 'providerCallId');
  }

  void handleSessionStarted(_ArtifactLogEntry entry) {
    sessionStartCount += 1;
    final sessionId = entry.sessionId;
    if (sessionId == null) {
      return;
    }

    final previousActive = _activeAttemptsBySessionId[sessionId];
    if (previousActive != null && previousActive.doneAt == null) {
      previousActive.supersededByRemount = true;
      previousActive.lastEventAt = entry.timestamp;
    }

    final attempt = _AttemptBuilder(
      attemptIndex: _attempts.length + 1,
      sessionId: sessionId,
      startedAt: entry.timestamp,
      lastEventAt: entry.timestamp,
    );
    attempt.phase = _readString(entry.fields, 'phase');
    attempt.sourcePath = _readString(entry.fields, 'sourcePath');
    _attempts.add(attempt);
    _activeAttemptsBySessionId[sessionId] = attempt;
    _lastAttemptsBySessionId[sessionId] = attempt;
  }

  void handleSourceProgressed(_ArtifactLogEntry entry) {
    _resolveAttempt(entry)?.sourceProgressCount += 1;
  }

  void handleRuntimeApplyStarted(_ArtifactLogEntry entry) {
    _resolveAttempt(entry)?.applyCount += 1;
  }

  void handleRuntimeApplyCompleted(_ArtifactLogEntry entry) {
    final attempt = _resolveAttempt(entry);
    if (attempt == null) {
      return;
    }
    attempt.runtimeApplyCompletedCount += 1;
    attempt.runtimeApplyCompletedAt ??= entry.timestamp;
  }

  void handleDomCommit(_ArtifactLogEntry entry) {
    final attempt = _resolveAttempt(entry);
    if (attempt == null) {
      return;
    }
    attempt.domCommitCount += 1;
    attempt.firstDomCommitAt ??= entry.timestamp;
  }

  void handleHeightSampled(_ArtifactLogEntry entry) {
    final attempt = _resolveAttempt(entry);
    if (attempt == null) {
      return;
    }
    attempt.heightSampleCount += 1;

    final sampledHeight =
        _readDouble(entry.fields, 'clampedHeight') ??
            _readDouble(entry.fields, 'rawHeight');
    final rawHeight = _readDouble(entry.fields, 'rawHeight');
    final previousAppliedHeight =
        _readDouble(entry.fields, 'previousAppliedHeight');
    final sampleDeltaFromPreviousAppliedPx =
        _readDouble(entry.fields, 'sampleDeltaFromPreviousAppliedPx') ??
            (sampledHeight != null && previousAppliedHeight != null
                ? sampledHeight - previousAppliedHeight
                : null);

    final rootScrollOutlierPx =
        _readDouble(entry.fields, 'rootScrollOutlierPx');
    final rootClientHeight =
        _readDouble(entry.fields, 'rootClientHeight');
    final hostViewportGapFromMeasuredHeightPx =
        _readDouble(entry.fields, 'hostViewportGapFromMeasuredHeightPx');
    final hostViewportGapFromClampedHeightPx =
        _readDouble(entry.fields, 'hostViewportGapFromClampedHeightPx');
    final hostViewportOvershootPx =
        _readDouble(entry.fields, 'hostViewportOvershootPx');
    final hostViewportProbeStatus =
        _readString(entry.fields, 'hostViewportProbeStatus');
    if (rootScrollOutlierPx != null) {
      final largestRootScrollOutlierPx =
          attempt.largestRootScrollOutlierPx ?? 0.0;
      if (rootScrollOutlierPx > largestRootScrollOutlierPx) {
        attempt.largestRootScrollOutlierPx = rootScrollOutlierPx;
      }
    }

    final artifactRectStretchPx =
        _readDouble(entry.fields, 'artifactRectStretchPx');
    if (artifactRectStretchPx != null) {
      final largestArtifactRectStretchPx =
          attempt.largestArtifactRectStretchPx ?? 0.0;
      if (artifactRectStretchPx > largestArtifactRectStretchPx) {
        attempt.largestArtifactRectStretchPx = artifactRectStretchPx;
      }
    }

    attempt._recordSampleHeight(
      rawHeight: rawHeight,
      sampledHeight: sampledHeight,
      previousAppliedHeight: previousAppliedHeight,
      rootClientHeight: rootClientHeight,
      hostViewportGapFromMeasuredHeightPx:
          hostViewportGapFromMeasuredHeightPx,
      hostViewportGapFromClampedHeightPx:
          hostViewportGapFromClampedHeightPx,
      hostViewportOvershootPx: hostViewportOvershootPx,
      hostViewportProbeStatus: hostViewportProbeStatus,
      sampleDeltaFromPreviousAppliedPx: sampleDeltaFromPreviousAppliedPx,
      artifactRectStretchPx: artifactRectStretchPx,
    );

    final sampledFromPendingFinalController =
        _readBool(entry.fields, 'sampledFromPendingFinalController') ?? false;
    final hasPendingFinalController =
        _readBool(entry.fields, 'hasPendingFinalController') ?? false;
    final controllerRole = _readString(entry.fields, 'controllerRole');
    final controllerId = _readString(entry.fields, 'controllerId');
    final activeControllerId = _readString(entry.fields, 'activeControllerId');
    final sampledPendingFinalBeforeVisibleTakeover =
        sampledFromPendingFinalController &&
            hasPendingFinalController &&
            (controllerRole == 'pendingFinal' ||
                (controllerId != null &&
                    activeControllerId != null &&
                    controllerId != activeControllerId));

    if (!sampledPendingFinalBeforeVisibleTakeover) {
      return;
    }

    attempt.sawPendingFinalControllerSample = true;
    final positiveJumpPx = sampleDeltaFromPreviousAppliedPx;
    if (positiveJumpPx == null || positiveJumpPx <= 30) {
      return;
    }

    final largestPendingFinalInjectionDeltaPx =
        attempt.pendingFinalInjectionDeltaPx ?? 0.0;
    if (positiveJumpPx <= largestPendingFinalInjectionDeltaPx) {
      return;
    }

    attempt.pendingFinalInjectionDeltaPx = positiveJumpPx;
    attempt.pendingFinalInjectionFromHeight =
        previousAppliedHeight ??
            (sampledHeight == null ? null : sampledHeight - positiveJumpPx);
    attempt.pendingFinalInjectionToHeight = sampledHeight;
  }

  void handleHeightApplied(_ArtifactLogEntry entry) {
    final attempt = _resolveAttempt(entry);
    if (attempt == null) {
      return;
    }
    attempt.heightAppliedCount += 1;
    final appliedHeight = _readDouble(entry.fields, 'appliedHeight');
    if (appliedHeight == null) {
      return;
    }
    final isPreviewTruncated =
        _readString(entry.fields, 'isPreviewTruncated') == 'true';

    attempt.finalAppliedHeight = appliedHeight;
    attempt.firstHeightAppliedAt ??= entry.timestamp;
    attempt.finalIsPreviewTruncated = isPreviewTruncated;

    final previousHeight = attempt.lastAppliedHeight;
    if (previousHeight != null) {
      if (appliedHeight < previousHeight) {
        attempt.decreaseCount += 1;
        attempt.pendingRecoveryBaselineHeight = appliedHeight;
      } else if (appliedHeight > previousHeight) {
        attempt.increaseCount += 1;
        final pendingRecoveryBaselineHeight =
            attempt.pendingRecoveryBaselineHeight;
        if (pendingRecoveryBaselineHeight != null) {
          final recoveryPx = appliedHeight - pendingRecoveryBaselineHeight;
          final largestRecoveryPx = attempt.largestRecoveryPx ?? 0.0;
          if (recoveryPx > largestRecoveryPx) {
            attempt.largestRecoveryPx = recoveryPx;
          }
        }
      }
    }

    final maxSeen = attempt.maxAppliedHeight;
    if (maxSeen == null || appliedHeight > maxSeen) {
      attempt.maxAppliedHeight = appliedHeight;
    } else {
      final dropPx = maxSeen - appliedHeight;
      final largestDropPx = attempt.largestDropPx ?? 0.0;
      if (dropPx > largestDropPx) {
        attempt.largestDropPx = dropPx;
      }
    }

    attempt.lastAppliedHeight = appliedHeight;
    final previousTruncated = attempt.lastIsPreviewTruncated;
    if (previousTruncated == true && !isPreviewTruncated) {
      attempt.sawTruncationRelease = true;
    }
    attempt.lastIsPreviewTruncated = isPreviewTruncated;
    attempt._maybeSetFirstSuccessfulRender(entry.timestamp);
  }

  void handlePhaseEvent(_ArtifactLogEntry entry) {
    final attempt = _resolveAttempt(entry);
    if (attempt == null) {
      return;
    }
    attempt.phase = _readString(entry.fields, 'phase') ?? attempt.phase;
    if (entry.message == 'artifact.preview.final_takeover') {
      attempt.sawFinalTakeoverEvent = true;
    }
  }

  void handleAnomaly(_ArtifactLogEntry entry) {
    final diagnosticCode = _readString(entry.fields, 'diagnosticCode');
    if (diagnosticCode != null) {
      _flowAnomalyCodes.add(diagnosticCode);
      _resolveAttempt(entry)?.anomalyCodes.add(diagnosticCode);
    }
  }

  void handleSessionDone(_ArtifactLogEntry entry) {
    sessionDoneCount += 1;
    final attempt = _resolveAttempt(entry) ??
        _createSyntheticAttempt(
          sessionId: entry.sessionId ?? 'unknown',
          timestamp: entry.timestamp,
        );
    attempt.doneAt = entry.timestamp;
    attempt.lastEventAt = entry.timestamp;
    attempt.phaseSummary = _readString(entry.fields, 'phaseSummary');
    attempt.verdict = _readString(entry.fields, 'verdict');
    attempt.heightPattern = _readString(entry.fields, 'heightPattern');
    attempt.sourcePath =
        _readString(entry.fields, 'sourcePath') ?? attempt.sourcePath;
    attempt.totalStreamingDurationMs =
        _readInt(entry.fields, 'totalStreamingDurationMs');
    attempt.firstSuccessfulRenderAtMs =
        _readInt(entry.fields, 'firstSuccessfulRenderAtMs') ??
            _readInt(entry.fields, 'timeToFirstSuccessfulRenderMs');
    if (attempt.totalStreamingDurationMs != null &&
        attempt.firstSuccessfulRenderAtMs != null) {
      attempt.tailWindowMs = attempt.totalStreamingDurationMs! -
          attempt.firstSuccessfulRenderAtMs!;
    }
    attempt.sourceProgressCount =
        _readInt(entry.fields, 'sourceProgressCount') ??
            attempt.sourceProgressCount;
    attempt.applyCount =
        _readInt(entry.fields, 'applyCount') ?? attempt.applyCount;
    attempt.domCommitCount =
        _readInt(entry.fields, 'domCommitCount') ?? attempt.domCommitCount;
    attempt.heightAppliedCount = _readInt(entry.fields, 'heightAppliedCount') ??
        attempt.heightAppliedCount;
    attempt.heightSampleCount = _readInt(entry.fields, 'heightSampleCount') ??
        attempt.heightSampleCount;
    attempt.maxAppliedHeight = _readDouble(entry.fields, 'maxAppliedHeight') ??
        attempt.maxAppliedHeight;
    attempt.finalAppliedHeight =
        _readDouble(entry.fields, 'finalAppliedHeight') ??
            attempt.finalAppliedHeight;
    attempt.largestDropPx =
        _readDouble(entry.fields, 'largestDropPx') ?? attempt.largestDropPx;

    final anomalyCodes = _readList(entry.fields, 'anomalyCodes');
    attempt.anomalyCodes.addAll(anomalyCodes);
    _flowAnomalyCodes.addAll(anomalyCodes);

    if (entry.sessionId != null) {
      _activeAttemptsBySessionId.remove(entry.sessionId);
    }
  }

  _AttemptBuilder _createSyntheticAttempt({
    required String sessionId,
    required DateTime timestamp,
  }) {
    final attempt = _AttemptBuilder(
      attemptIndex: _attempts.length + 1,
      sessionId: sessionId,
      startedAt: null,
      lastEventAt: timestamp,
    );
    _attempts.add(attempt);
    _lastAttemptsBySessionId[sessionId] = attempt;
    return attempt;
  }

  _AttemptBuilder? _resolveAttempt(_ArtifactLogEntry entry) {
    final sessionId = entry.sessionId;
    if (sessionId == null) {
      return null;
    }
    final active = _activeAttemptsBySessionId[sessionId];
    if (active != null) {
      active.lastEventAt = entry.timestamp;
      return active;
    }
    final last = _lastAttemptsBySessionId[sessionId];
    if (last != null) {
      last.lastEventAt = entry.timestamp;
    }
    return last;
  }

  ArtifactRenderFlowAnalysis? build() {
    final first = firstEventAt;
    final last = lastEventAt;
    if (first == null || last == null || _attempts.isEmpty) {
      return null;
    }

    final attempts =
        _attempts.map((attempt) => attempt.build()).toList(growable: false);
    final primaryAttempt = attempts.isEmpty
        ? null
        : (attempts.toList(growable: false)
              ..sort((a, b) {
                final scoreCompare =
                    _attemptScore(b).compareTo(_attemptScore(a));
                if (scoreCompare != 0) {
                  return scoreCompare;
                }
                return b.lastEventAt.compareTo(a.lastEventAt);
              }))
            .first;

    final uniqueSessionIds =
        attempts.map((attempt) => attempt.sessionId).toSet();
    final remountEvidence = <String>[
      if (attempts.length > 1) 'multiple_render_attempts_same_flow',
      if (uniqueSessionIds.length > 1) 'multiple_session_ids_same_flow',
      if (sessionStartCount > uniqueSessionIds.length)
        'reused_session_id_across_multiple_attempts',
    ];
    final summarySignals = _buildSummarySignals(
      attempts: attempts,
      remountEvidence: remountEvidence,
    );

    return ArtifactRenderFlowAnalysis(
      flowId: flowId,
      usedDerivedFlowId: usedDerivedFlowId,
      turnId: turnId,
      artifactId: artifactId,
      providerCallId: providerCallId,
      firstEventAt: first,
      lastEventAt: last,
      renderAttemptCount: attempts.length,
      uniqueSessionIdCount: uniqueSessionIds.length,
      sessionStartCount: sessionStartCount,
      sessionDoneCount: sessionDoneCount,
      anomalyCodes: _flowAnomalyCodes.toList(growable: false)..sort(),
      remountEvidence: remountEvidence,
      summarySignals: summarySignals,
      summaryLabel: summarySignals.isEmpty ? 'normal' : summarySignals.join(' + '),
      incidentReport: _buildIncidentReport(
        summarySignals: summarySignals,
        attempts: attempts,
        uniqueSessionIds: uniqueSessionIds.length,
      ),
      primaryAttempt: primaryAttempt,
      attempts: attempts,
    );
  }

  List<String> _buildSummarySignals({
    required List<ArtifactRenderAttemptAnalysis> attempts,
    required List<String> remountEvidence,
  }) {
    final signals = <String>[];
    if (remountEvidence.isNotEmpty) {
      signals.add('remount');
    }
    if (attempts.any(
      (attempt) =>
          attempt.anomalyCodes.contains(
            'artifact_first_render_in_final_second',
          ) ||
          (attempt.totalStreamingDurationMs != null &&
              attempt.firstSuccessfulRenderAtMs != null &&
              attempt.totalStreamingDurationMs! > 3000 &&
              attempt.tailWindowMs != null &&
              attempt.tailWindowMs! <= 1000),
    )) {
      signals.add('late_first_render');
    }
    if (attempts.any((attempt) => attempt.heightPattern == 'finalTakeoverDrop')) {
      signals.add('final_takeover_drop');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains('height_drop_after_truncation_release'),
    )) {
      signals.add('truncation_release_drop');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains(
            'height_recovered_over_30px_after_drop',
          ),
    )) {
      signals.add('drop_then_recover');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains(
            'pending_final_height_injection_before_takeover',
          ),
    )) {
      signals.add('pending_final_injection');
    }
    if (attempts.any(
      (attempt) => attempt.derivedSignals.contains('root_scroll_outlier_sampled'),
    )) {
      signals.add('root_scroll_outlier');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains('artifact_rect_stretch_sampled'),
    )) {
      signals.add('artifact_rect_stretch');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains('sample_height_spike_then_rollback'),
    )) {
      signals.add('sample_spike_rollback');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains(
            'sampled_content_collapse_before_apply',
          ),
    )) {
      signals.add('sampled_content_collapse');
    }
    if (attempts.any(
      (attempt) => attempt.derivedSignals.contains('viewport_content_gap_sampled'),
    )) {
      signals.add('viewport_content_gap');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains('root_viewport_content_gap_sampled'),
    )) {
      signals.add('root_viewport_gap');
    }
    if (attempts.any(
      (attempt) => attempt.derivedSignals.contains('height_clamp_lift_sampled'),
    )) {
      signals.add('clamp_lift');
    }
    if (attempts.any(
      (attempt) => attempt.derivedSignals.contains('host_viewport_measured_gap_sampled'),
    )) {
      signals.add('host_viewport_gap');
    }
    if (attempts.any(
      (attempt) => attempt.derivedSignals.contains('host_viewport_overshoot_sampled'),
    )) {
      signals.add('host_viewport_overshoot');
    }
    if (attempts.any(
      (attempt) =>
          attempt.derivedSignals.contains('host_viewport_probe_never_resolved'),
    )) {
      signals.add('host_viewport_probe_missing');
    }
    return signals;
  }

  ArtifactRenderIncidentReport _buildIncidentReport({
    required List<String> summarySignals,
    required List<ArtifactRenderAttemptAnalysis> attempts,
    required int uniqueSessionIds,
  }) {
    final findings = <String>[];
    final primaryAttempt = attempts.isEmpty
        ? null
        : (attempts.toList(growable: false)
              ..sort((a, b) {
                final scoreCompare =
                    _attemptScore(b).compareTo(_attemptScore(a));
                if (scoreCompare != 0) {
                  return scoreCompare;
                }
                return b.lastEventAt.compareTo(a.lastEventAt);
              }))
            .first;

    if (summarySignals.contains('remount')) {
      findings.add(
        'Flow remounted across ${attempts.length} attempts and $uniqueSessionIds sessionIds.',
      );
    }
    if (summarySignals.contains('late_first_render') && primaryAttempt != null) {
      final tailWindowMs = primaryAttempt.tailWindowMs;
      final durationMs = primaryAttempt.totalStreamingDurationMs;
      if (tailWindowMs != null && durationMs != null) {
        findings.add(
          'Primary attempt first rendered in the final ${tailWindowMs}ms of a ${durationMs}ms stream.',
        );
      }
    }
    if (summarySignals.contains('pending_final_injection') &&
        primaryAttempt != null) {
      final fromHeight = primaryAttempt.pendingFinalInjectionFromHeight;
      final toHeight = primaryAttempt.pendingFinalInjectionToHeight;
      if (fromHeight != null && toHeight != null) {
        findings.add(
          'Primary attempt sampled a pending-final controller height jump before takeover (${_fmtDouble(fromHeight)}px -> ${_fmtDouble(toHeight)}px).',
        );
      }
    }
    if (summarySignals.contains('root_scroll_outlier') && primaryAttempt != null) {
      final rootScrollOutlierPx = primaryAttempt.largestRootScrollOutlierPx;
      if (rootScrollOutlierPx != null && rootScrollOutlierPx > 0) {
        final suffix = summarySignals.contains('pending_final_injection')
            ? ' during the jump.'
            : ' during sampling.';
        findings.add(
          'Primary attempt saw rootScroll exceed artifact/body metrics by ${_fmtDouble(rootScrollOutlierPx)}px$suffix',
        );
      }
    }
    if (summarySignals.contains('artifact_rect_stretch') &&
        primaryAttempt != null) {
      final artifactRectStretchPx =
          primaryAttempt.largestArtifactRectStretchPx;
      if (artifactRectStretchPx != null && artifactRectStretchPx > 0) {
        findings.add(
          'Primary attempt saw artifactRect exceed intrinsic artifact metrics by ${_fmtDouble(artifactRectStretchPx)}px.',
        );
      }
    }
    if (summarySignals.contains('sample_spike_rollback') &&
        primaryAttempt != null) {
      final fromHeight = primaryAttempt.sampleSpikeFromHeight;
      final peakHeight = primaryAttempt.sampleSpikePeakHeight;
      final rollbackHeight = primaryAttempt.sampleSpikeRollbackHeight;
      if (fromHeight != null &&
          peakHeight != null &&
          rollbackHeight != null) {
        findings.add(
          'Primary attempt sampled a short-lived height spike before rollback (${_fmtDouble(fromHeight)}px -> ${_fmtDouble(peakHeight)}px -> ${_fmtDouble(rollbackHeight)}px).',
        );
      }
    }
    if (summarySignals.contains('sampled_content_collapse') &&
        primaryAttempt != null) {
      final fromHeight = primaryAttempt.sampledCollapseFromHeight;
      final rawHeight = primaryAttempt.sampledCollapseRawHeight;
      final toHeight = primaryAttempt.sampledCollapseToHeight;
      if (fromHeight != null && rawHeight != null && toHeight != null) {
        findings.add(
          'Primary attempt sampled a content collapse before apply (${_fmtDouble(fromHeight)}px -> ${_fmtDouble(rawHeight)}px raw, ${_fmtDouble(toHeight)}px clamped).',
        );
      }
      final probeStatus =
          primaryAttempt.sampledCollapseHostViewportProbeStatus;
      if (probeStatus != null && probeStatus != 'ok') {
        findings.add(
          'Primary attempt could not resolve the host viewport probe at the collapse sample (status=$probeStatus).',
        );
      }
    }
    if (summarySignals.contains('viewport_content_gap') &&
        primaryAttempt != null) {
      final gapPx = primaryAttempt.largestViewportContentGapPx;
      if (gapPx != null && gapPx > 0) {
        findings.add(
          'Primary attempt saw host viewport exceed intrinsic content by ${_fmtDouble(gapPx)}px during sampling.',
        );
      }
    }
    if (summarySignals.contains('root_viewport_gap') &&
        primaryAttempt != null) {
      final gapPx = primaryAttempt.largestRootViewportContentGapPx;
      if (gapPx != null && gapPx > 0) {
        findings.add(
          'Primary attempt saw root viewport exceed intrinsic content by ${_fmtDouble(gapPx)}px during sampling.',
        );
      }
    }
    if (summarySignals.contains('clamp_lift') && primaryAttempt != null) {
      final liftPx = primaryAttempt.largestClampLiftPx;
      if (liftPx != null && liftPx > 0) {
        findings.add(
          'Primary attempt lifted sampled height by ${_fmtDouble(liftPx)}px via preview height clamp.',
        );
      }
    }
    if (summarySignals.contains('host_viewport_gap') && primaryAttempt != null) {
      final gapPx = primaryAttempt.largestHostViewportMeasuredGapPx;
      if (gapPx != null && gapPx > 0) {
        findings.add(
          'Primary attempt saw host render viewport exceed intrinsic content by ${_fmtDouble(gapPx)}px during sampling.',
        );
      }
    }
    if (summarySignals.contains('host_viewport_overshoot') &&
        primaryAttempt != null) {
      final overshootPx = primaryAttempt.largestHostViewportOvershootPx;
      if (overshootPx != null && overshootPx > 0) {
        findings.add(
          'Primary attempt saw host render viewport exceed configured preview height by ${_fmtDouble(overshootPx)}px during sampling.',
        );
      }
    }
    if (summarySignals.contains('host_viewport_probe_missing') &&
        primaryAttempt != null) {
      final statusCounts =
          _formatStatusCounts(primaryAttempt.hostViewportProbeStatusCounts);
      if (statusCounts.isNotEmpty) {
        findings.add(
          'Primary attempt never resolved the host viewport probe during sampling ($statusCounts).',
        );
      }
    }
    if (summarySignals.contains('truncation_release_drop') &&
        primaryAttempt != null) {
      findings.add(
        'Primary final takeover attempt dropped ${_fmtDouble(primaryAttempt.largestDropPx)}px after truncation release (${_fmtDouble(primaryAttempt.maxAppliedHeight)}px -> ${_fmtDouble(primaryAttempt.finalAppliedHeight)}px).',
      );
    } else if (summarySignals.contains('final_takeover_drop') &&
        primaryAttempt != null) {
      findings.add(
        'Primary final takeover attempt dropped ${_fmtDouble(primaryAttempt.largestDropPx)}px (${_fmtDouble(primaryAttempt.maxAppliedHeight)}px -> ${_fmtDouble(primaryAttempt.finalAppliedHeight)}px).',
      );
    }
    if (summarySignals.contains('drop_then_recover') && primaryAttempt != null) {
      findings.add(
        'Primary attempt recovered ${_fmtDouble(primaryAttempt.largestRecoveryPx)}px after the drop.',
      );
    }

    return ArtifactRenderIncidentReport(
      headline: summarySignals.isEmpty ? 'normal' : summarySignals.join(' + '),
      findings: findings,
    );
  }

  int _attemptScore(ArtifactRenderAttemptAnalysis attempt) {
    final duration = attempt.totalStreamingDurationMs ?? 0;
    final firstRender = attempt.firstSuccessfulRenderAtMs ?? 0;
    final anomalyBoost = attempt.anomalyCodes.isNotEmpty ? 100000 : 0;
    final doneBoost = attempt.doneAt != null ? 10000 : 0;
    return anomalyBoost +
        doneBoost +
        (attempt.heightAppliedCount * 1000) +
        (attempt.domCommitCount * 100) +
        (attempt.applyCount * 10) +
        (attempt.sourceProgressCount * 5) +
        duration +
        firstRender;
  }
}

class _AttemptBuilder {
  _AttemptBuilder({
    required this.attemptIndex,
    required this.sessionId,
    required this.startedAt,
    required this.lastEventAt,
  });

  final int attemptIndex;
  final String sessionId;
  final DateTime? startedAt;
  DateTime lastEventAt;
  DateTime? doneAt;
  String? phase;
  String? phaseSummary;
  String? verdict;
  String? heightPattern;
  String? sourcePath;
  bool supersededByRemount = false;
  final Set<String> anomalyCodes = <String>{};
  int sourceProgressCount = 0;
  int applyCount = 0;
  int runtimeApplyCompletedCount = 0;
  int domCommitCount = 0;
  int heightAppliedCount = 0;
  int heightSampleCount = 0;
  int increaseCount = 0;
  int decreaseCount = 0;
  int? totalStreamingDurationMs;
  int? firstSuccessfulRenderAtMs;
  int? tailWindowMs;
  DateTime? runtimeApplyCompletedAt;
  DateTime? firstDomCommitAt;
  DateTime? firstHeightAppliedAt;
  DateTime? firstSuccessfulRenderAt;
  bool sawFinalTakeoverEvent = false;
  double? lastAppliedHeight;
  double? maxAppliedHeight;
  double? finalAppliedHeight;
  double? largestDropPx;
  double? largestRecoveryPx;
  bool sawPendingFinalControllerSample = false;
  double? pendingFinalInjectionFromHeight;
  double? pendingFinalInjectionToHeight;
  double? pendingFinalInjectionDeltaPx;
  double? largestRootScrollOutlierPx;
  double? largestArtifactRectStretchPx;
  double? sampleSpikeFromHeight;
  double? sampleSpikePeakHeight;
  double? sampleSpikeRollbackHeight;
  double? sampleSpikeDeltaPx;
  double? sampledCollapseFromHeight;
  double? sampledCollapseToHeight;
  double? sampledCollapseRawHeight;
  double? sampledCollapseDeltaPx;
  String? sampledCollapseHostViewportProbeStatus;
  double? largestViewportContentGapPx;
  double? largestRootViewportContentGapPx;
  double? largestClampLiftPx;
  double? largestHostViewportMeasuredGapPx;
  double? largestHostViewportClampedGapPx;
  double? largestHostViewportOvershootPx;
  final Map<String, int> hostViewportProbeStatusCounts = <String, int>{};
  final List<_RecentSampleHeight> _recentSampleHeights = <_RecentSampleHeight>[];
  double? pendingRecoveryBaselineHeight;
  bool? lastIsPreviewTruncated;
  bool finalIsPreviewTruncated = false;
  bool sawTruncationRelease = false;

  ArtifactRenderAttemptAnalysis build() {
    final derivedPhaseSummary =
        phaseSummary ?? (sawFinalTakeoverEvent ? 'runtime->finalTakeover' : phase);
    final derivedFirstSuccessfulRenderAtMs =
        firstSuccessfulRenderAtMs ?? _deriveFirstSuccessfulRenderAtMs();
    final derivedTotalStreamingDurationMs =
        totalStreamingDurationMs ?? _deriveTotalStreamingDurationMs();
    final derivedTailWindowMs =
        tailWindowMs ??
            (derivedTotalStreamingDurationMs != null &&
                    derivedFirstSuccessfulRenderAtMs != null
                ? derivedTotalStreamingDurationMs -
                    derivedFirstSuccessfulRenderAtMs
                : null);
    final derivedLargestDropPx = largestDropPx ?? 0.0;
    final derivedHeightPattern = heightPattern ?? _deriveHeightPattern();
    final derivedLargestRecoveryPx = largestRecoveryPx ?? 0.0;
    final derivedSignals = _deriveSignals(
      derivedLargestDropPx: derivedLargestDropPx,
      derivedLargestRecoveryPx: derivedLargestRecoveryPx,
    );

    return ArtifactRenderAttemptAnalysis(
      attemptIndex: attemptIndex,
      sessionId: sessionId,
      startedAt: startedAt,
      lastEventAt: lastEventAt,
      doneAt: doneAt,
      phase: phase,
      phaseSummary: derivedPhaseSummary,
      verdict: verdict,
      heightPattern: derivedHeightPattern,
      sourcePath: sourcePath,
      supersededByRemount: supersededByRemount,
      anomalyCodes: anomalyCodes.toList(growable: false)..sort(),
      sourceProgressCount: sourceProgressCount,
      applyCount: applyCount,
      domCommitCount: domCommitCount,
      heightAppliedCount: heightAppliedCount,
      heightSampleCount: heightSampleCount,
      totalStreamingDurationMs: derivedTotalStreamingDurationMs,
      firstSuccessfulRenderAtMs: derivedFirstSuccessfulRenderAtMs,
      tailWindowMs: derivedTailWindowMs,
      maxAppliedHeight: maxAppliedHeight,
      finalAppliedHeight: finalAppliedHeight,
      largestDropPx: derivedLargestDropPx,
      largestRecoveryPx: derivedLargestRecoveryPx,
      pendingFinalInjectionFromHeight: pendingFinalInjectionFromHeight,
      pendingFinalInjectionToHeight: pendingFinalInjectionToHeight,
      pendingFinalInjectionDeltaPx: pendingFinalInjectionDeltaPx,
      largestRootScrollOutlierPx: largestRootScrollOutlierPx,
      largestArtifactRectStretchPx: largestArtifactRectStretchPx,
      sampleSpikeFromHeight: sampleSpikeFromHeight,
      sampleSpikePeakHeight: sampleSpikePeakHeight,
      sampleSpikeRollbackHeight: sampleSpikeRollbackHeight,
      sampleSpikeDeltaPx: sampleSpikeDeltaPx,
      sampledCollapseFromHeight: sampledCollapseFromHeight,
      sampledCollapseToHeight: sampledCollapseToHeight,
      sampledCollapseRawHeight: sampledCollapseRawHeight,
      sampledCollapseDeltaPx: sampledCollapseDeltaPx,
      sampledCollapseHostViewportProbeStatus:
          sampledCollapseHostViewportProbeStatus,
      largestViewportContentGapPx: largestViewportContentGapPx,
      largestRootViewportContentGapPx: largestRootViewportContentGapPx,
      largestClampLiftPx: largestClampLiftPx,
      largestHostViewportMeasuredGapPx: largestHostViewportMeasuredGapPx,
      largestHostViewportClampedGapPx: largestHostViewportClampedGapPx,
      largestHostViewportOvershootPx: largestHostViewportOvershootPx,
      hostViewportProbeStatusCounts: Map<String, int>.fromEntries(
        hostViewportProbeStatusCounts.entries.toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key)),
      ),
      derivedSignals: derivedSignals,
    );
  }

  void _recordSampleHeight({
    required double? rawHeight,
    required double? sampledHeight,
    required double? previousAppliedHeight,
    required double? rootClientHeight,
    required double? hostViewportGapFromMeasuredHeightPx,
    required double? hostViewportGapFromClampedHeightPx,
    required double? hostViewportOvershootPx,
    required String? hostViewportProbeStatus,
    required double? sampleDeltaFromPreviousAppliedPx,
    required double? artifactRectStretchPx,
  }) {
    if (sampledHeight == null) {
      return;
    }
    if (hostViewportProbeStatus != null && hostViewportProbeStatus.isNotEmpty) {
      hostViewportProbeStatusCounts.update(
        hostViewportProbeStatus,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final viewportContentGapPx =
        previousAppliedHeight != null && rawHeight != null
            ? previousAppliedHeight - rawHeight
            : null;
    if (viewportContentGapPx != null && viewportContentGapPx > 0) {
      final largestGapPx = largestViewportContentGapPx ?? 0.0;
      if (viewportContentGapPx > largestGapPx) {
        largestViewportContentGapPx = viewportContentGapPx;
      }
    }
    final rootViewportContentGapPx =
        rootClientHeight != null && rawHeight != null
            ? rootClientHeight - rawHeight
            : null;
    if (rootViewportContentGapPx != null && rootViewportContentGapPx > 0) {
      final largestRootGapPx = largestRootViewportContentGapPx ?? 0.0;
      if (rootViewportContentGapPx > largestRootGapPx) {
        largestRootViewportContentGapPx = rootViewportContentGapPx;
      }
    }
    if (rawHeight != null) {
      final clampLiftPx = sampledHeight - rawHeight;
      if (clampLiftPx > 0) {
        final largestLiftPx = largestClampLiftPx ?? 0.0;
        if (clampLiftPx > largestLiftPx) {
          largestClampLiftPx = clampLiftPx;
        }
      }
    }
    if (hostViewportGapFromMeasuredHeightPx != null &&
        hostViewportGapFromMeasuredHeightPx > 0) {
      final largestGapPx = largestHostViewportMeasuredGapPx ?? 0.0;
      if (hostViewportGapFromMeasuredHeightPx > largestGapPx) {
        largestHostViewportMeasuredGapPx = hostViewportGapFromMeasuredHeightPx;
      }
    }
    if (hostViewportGapFromClampedHeightPx != null &&
        hostViewportGapFromClampedHeightPx > 0) {
      final largestGapPx = largestHostViewportClampedGapPx ?? 0.0;
      if (hostViewportGapFromClampedHeightPx > largestGapPx) {
        largestHostViewportClampedGapPx = hostViewportGapFromClampedHeightPx;
      }
    }
    if (hostViewportOvershootPx != null && hostViewportOvershootPx > 0) {
      final largestOvershootPx = largestHostViewportOvershootPx ?? 0.0;
      if (hostViewportOvershootPx > largestOvershootPx) {
        largestHostViewportOvershootPx = hostViewportOvershootPx;
      }
    }

    final collapseDeltaPx =
        previousAppliedHeight != null ? previousAppliedHeight - sampledHeight : null;
    if (collapseDeltaPx != null && collapseDeltaPx > 30) {
      final existingCollapseDeltaPx = sampledCollapseDeltaPx ?? 0.0;
      if (collapseDeltaPx > existingCollapseDeltaPx) {
        sampledCollapseFromHeight = previousAppliedHeight;
        sampledCollapseToHeight = sampledHeight;
        sampledCollapseRawHeight = rawHeight;
        sampledCollapseDeltaPx = collapseDeltaPx;
        sampledCollapseHostViewportProbeStatus = hostViewportProbeStatus;
      }
    }

    _recentSampleHeights.add(
      _RecentSampleHeight(
        height: sampledHeight,
        deltaFromPreviousAppliedPx: sampleDeltaFromPreviousAppliedPx,
        artifactRectStretchPx: artifactRectStretchPx ?? 0.0,
      ),
    );
    while (_recentSampleHeights.length > 3) {
      _recentSampleHeights.removeAt(0);
    }

    if (_recentSampleHeights.length < 3) {
      return;
    }

    final first = _recentSampleHeights[0];
    final middle = _recentSampleHeights[1];
    final last = _recentSampleHeights[2];
    final spikeDelta = middle.height - first.height;
    final rollbackDelta = (last.height - first.height).abs();
    if (spikeDelta <= 30 || rollbackDelta > 10) {
      return;
    }
    final sawStretch =
        middle.artifactRectStretchPx > 0 || first.artifactRectStretchPx > 0;
    final existingSpikeDelta = sampleSpikeDeltaPx ?? 0.0;
    if (!sawStretch || spikeDelta <= existingSpikeDelta) {
      return;
    }

    sampleSpikeFromHeight = first.height;
    sampleSpikePeakHeight = middle.height;
    sampleSpikeRollbackHeight = last.height;
    sampleSpikeDeltaPx = spikeDelta;
  }

  void _maybeSetFirstSuccessfulRender(DateTime timestamp) {
    if (firstSuccessfulRenderAt != null) {
      return;
    }
    if (runtimeApplyCompletedAt == null) {
      return;
    }
    if (firstDomCommitAt == null) {
      return;
    }
    if (heightAppliedCount < 1) {
      return;
    }
    firstSuccessfulRenderAt = timestamp;
  }

  int? _deriveTotalStreamingDurationMs() {
    final startedAtValue = startedAt;
    if (startedAtValue == null) {
      return null;
    }
    return lastEventAt.difference(startedAtValue).inMilliseconds;
  }

  int? _deriveFirstSuccessfulRenderAtMs() {
    final startedAtValue = startedAt;
    final firstSuccessfulRenderAtValue = firstSuccessfulRenderAt;
    if (startedAtValue == null || firstSuccessfulRenderAtValue == null) {
      return null;
    }
    return firstSuccessfulRenderAtValue
        .difference(startedAtValue)
        .inMilliseconds;
  }

  String _deriveHeightPattern() {
    if (heightAppliedCount == 0) {
      return 'noHeightSignal';
    }
    if ((sawFinalTakeoverEvent || phase == 'finalTakeover') &&
        anomalyCodes.contains('artifact_height_drop_over_30px')) {
      return 'finalTakeoverDrop';
    }
    if (increaseCount > 1 && decreaseCount > 1) {
      return 'sawtooth';
    }
    if (anomalyCodes.contains('artifact_height_drop_over_30px')) {
      return 'overshootThenDrop';
    }
    return 'monotonicGrowth';
  }

  List<String> _deriveSignals({
    required double derivedLargestDropPx,
    required double derivedLargestRecoveryPx,
  }) {
    final signals = <String>[];
    if (sawTruncationRelease) {
      signals.add('preview_truncation_released');
    }
    if (sawTruncationRelease && derivedLargestDropPx > 30) {
      signals.add('height_drop_after_truncation_release');
    }
    if (derivedLargestRecoveryPx > 30) {
      signals.add('height_recovered_over_30px_after_drop');
    }
    if ((pendingFinalInjectionDeltaPx ?? 0.0) > 30) {
      signals.add('pending_final_height_injection_before_takeover');
    }
    if ((largestRootScrollOutlierPx ?? 0.0) > 30) {
      signals.add('root_scroll_outlier_sampled');
    }
    if ((largestArtifactRectStretchPx ?? 0.0) > 30) {
      signals.add('artifact_rect_stretch_sampled');
    }
    if ((sampleSpikeDeltaPx ?? 0.0) > 30) {
      signals.add('sample_height_spike_then_rollback');
    }
    if ((sampledCollapseDeltaPx ?? 0.0) > 30) {
      signals.add('sampled_content_collapse_before_apply');
    }
    if ((sampledCollapseDeltaPx ?? 0.0) > 30 &&
        (largestViewportContentGapPx ?? 0.0) > 30) {
      signals.add('viewport_content_gap_sampled');
    }
    if ((largestRootViewportContentGapPx ?? 0.0) > 30) {
      signals.add('root_viewport_content_gap_sampled');
    }
    if ((largestClampLiftPx ?? 0.0) > 30) {
      signals.add('height_clamp_lift_sampled');
    }
    if ((largestHostViewportMeasuredGapPx ?? 0.0) > 30) {
      signals.add('host_viewport_measured_gap_sampled');
    }
    if ((largestHostViewportOvershootPx ?? 0.0) > 30) {
      signals.add('host_viewport_overshoot_sampled');
    }
    final hostViewportProbeSampleCount = hostViewportProbeStatusCounts.values
        .fold<int>(0, (sum, count) => sum + count);
    final hostViewportProbeOkCount = hostViewportProbeStatusCounts['ok'] ?? 0;
    if (hostViewportProbeSampleCount > 0 && hostViewportProbeOkCount == 0) {
      signals.add('host_viewport_probe_never_resolved');
    }
    return signals;
  }
}

String _formatStatusCounts(Map<String, int> statusCounts) {
  if (statusCounts.isEmpty) {
    return '';
  }
  final entries = statusCounts.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join(', ');
}

class _RecentSampleHeight {
  const _RecentSampleHeight({
    required this.height,
    required this.deltaFromPreviousAppliedPx,
    required this.artifactRectStretchPx,
  });

  final double height;
  final double? deltaFromPreviousAppliedPx;
  final double artifactRectStretchPx;
}

class _ArtifactLogEntry {
  _ArtifactLogEntry({
    required this.timestamp,
    required this.message,
    required this.fields,
  }) : sessionId = _readString(fields, 'sessionId');

  final DateTime timestamp;
  final String message;
  final Map<String, String> fields;
  final String? sessionId;

  static _ArtifactLogEntry? tryParse(String line) {
    if (!line.contains('[ArtifactRenderSessionRecorder] artifact.preview.')) {
      return null;
    }

    final match = RegExp(
      r'^(\S+)\s+\S+\s+\[[^\]]+\]\s+\[[^\]]+\]\s+(\S+)(?:\s+(.*))?$',
    ).firstMatch(line.trim());
    if (match == null) {
      return null;
    }

    final timestamp = DateTime.tryParse(match.group(1) ?? '');
    final message = match.group(2);
    if (timestamp == null || message == null) {
      return null;
    }

    return _ArtifactLogEntry(
      timestamp: timestamp,
      message: message,
      fields: _parseFields(match.group(3) ?? ''),
    );
  }

  static Map<String, String> _parseFields(String raw) {
    final result = <String, String>{};
    if (raw.trim().isEmpty) {
      return result;
    }

    String? currentKey;
    var valueStart = 0;
    var inQuotes = false;
    var bracketDepth = 0;
    var braceDepth = 0;
    var i = 0;

    bool isKeyStart(int index) {
      if (index < 0 || index >= raw.length) {
        return false;
      }
      if (index > 0 && raw[index - 1] != ' ') {
        return false;
      }
      final first = raw.codeUnitAt(index);
      final isLetter =
          (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
      if (!isLetter) {
        return false;
      }
      var cursor = index + 1;
      while (cursor < raw.length) {
        final code = raw.codeUnitAt(cursor);
        final isAlphaNumeric = (code >= 48 && code <= 57) ||
            (code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122);
        if (!isAlphaNumeric) {
          return raw[cursor] == '=';
        }
        cursor += 1;
      }
      return false;
    }

    while (i < raw.length) {
      final char = raw[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        i += 1;
        continue;
      }
      if (!inQuotes) {
        if (char == '[') {
          bracketDepth += 1;
        } else if (char == ']') {
          bracketDepth = bracketDepth > 0 ? bracketDepth - 1 : 0;
        } else if (char == '{') {
          braceDepth += 1;
        } else if (char == '}') {
          braceDepth = braceDepth > 0 ? braceDepth - 1 : 0;
        }
      }

      if (!inQuotes && bracketDepth == 0 && braceDepth == 0 && isKeyStart(i)) {
        var keyEnd = i + 1;
        while (keyEnd < raw.length && raw[keyEnd] != '=') {
          keyEnd += 1;
        }
        if (keyEnd >= raw.length) {
          break;
        }

        if (currentKey != null) {
          result[currentKey] = raw.substring(valueStart, i).trim();
        }
        currentKey = raw.substring(i, keyEnd);
        valueStart = keyEnd + 1;
        i = valueStart;
        continue;
      }

      i += 1;
    }

    if (currentKey != null && valueStart <= raw.length) {
      result[currentKey] = raw.substring(valueStart).trim();
    }
    return result;
  }
}

String? _readString(Map<String, String> fields, String key) {
  final value = fields[key]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

int? _readInt(Map<String, String> fields, String key) {
  final raw = _readString(fields, key);
  return raw == null ? null : int.tryParse(raw);
}

double? _readDouble(Map<String, String> fields, String key) {
  final raw = _readString(fields, key);
  return raw == null ? null : double.tryParse(raw);
}

bool? _readBool(Map<String, String> fields, String key) {
  final raw = _readString(fields, key);
  if (raw == null) {
    return null;
  }
  switch (raw.toLowerCase()) {
    case 'true':
    case '1':
      return true;
    case 'false':
    case '0':
      return false;
  }
  return null;
}

List<String> _readList(Map<String, String> fields, String key) {
  final raw = _readString(fields, key);
  if (raw == null || raw == '[]') {
    return const <String>[];
  }
  if (raw.startsWith('[') && raw.endsWith(']')) {
    final inner = raw.substring(1, raw.length - 1).trim();
    if (inner.isEmpty) {
      return const <String>[];
    }
    return inner
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return <String>[raw];
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

String _fmtDouble(double? value) {
  if (value == null) {
    return '-';
  }
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}
