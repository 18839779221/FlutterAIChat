/// Runtime phase marker for one inline artifact render session.
enum ArtifactRenderPhase {
  runtime,
  finalTakeover,
}

/// Session verdict emitted by artifact render observability.
enum ArtifactRenderSessionVerdict {
  normal,
  anomalous,
}

/// Height-shape summary derived from one render session.
enum ArtifactRenderHeightPattern {
  monotonicGrowth,
  overshootThenDrop,
  sawtooth,
  finalTakeoverDrop,
  noHeightSignal,
}

/// Final runtime-only summary for one inline artifact render session.
class ArtifactRenderSessionSnapshot {
  const ArtifactRenderSessionSnapshot({
    required this.sessionId,
    required this.turnId,
    required this.artifactId,
    required this.sourcePath,
    required this.verdict,
    required this.anomalyCodes,
    required this.heightPattern,
    required this.maxAppliedHeight,
    required this.finalAppliedHeight,
    required this.largestDropPx,
    required this.totalStreamingDurationMs,
    required this.firstSuccessfulRenderAtMs,
    required this.sourceProgressCount,
    required this.applyCount,
    required this.domCommitCount,
    required this.heightSampleCount,
    required this.heightAppliedCount,
    required this.phaseSummary,
  });

  final String sessionId;
  final String turnId;
  final String artifactId;
  final String sourcePath;
  final ArtifactRenderSessionVerdict verdict;
  final List<String> anomalyCodes;
  final ArtifactRenderHeightPattern heightPattern;
  final double? maxAppliedHeight;
  final double? finalAppliedHeight;
  final double largestDropPx;
  final int totalStreamingDurationMs;
  final int? firstSuccessfulRenderAtMs;
  final int sourceProgressCount;
  final int applyCount;
  final int domCommitCount;
  final int heightSampleCount;
  final int heightAppliedCount;
  final String phaseSummary;
}
