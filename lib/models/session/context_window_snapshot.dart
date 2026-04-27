import 'context_window_segment.dart';

class ContextWindowSnapshot {
  /// Runtime model name used to resolve the current budget profile.
  final String modelName;

  /// Provider-advertised or app-safe context window upper bound.
  final int maxContextTokens;

  /// Budget currently available to planner-visible input after reserves.
  final int usableInputBudget;

  /// Ratio at which history compaction starts to trigger.
  final double compressionTriggerRatio;

  /// Estimated total tokens that would be sent as planner input.
  final int totalEstimatedInputTokens;

  /// Share of the full context window currently consumed by planner input.
  final double totalWindowUsageRatio;

  /// Share of the planner-usable input budget currently consumed.
  final double usableInputUsageRatio;

  /// Whether older history was compacted into snapshot summary during build.
  final bool didCompactHistory;

  /// Last turn covered by the active snapshot summary, when present.
  final int? snapshotCoveredUntilTurnId;

  /// Number of completed turns still retained in raw recent form.
  final int recentCompletedTurnCount;

  /// Ordered context and reserve segments rendered by the UI.
  final List<ContextWindowSegment> segments;

  const ContextWindowSnapshot({
    required this.modelName,
    required this.maxContextTokens,
    required this.usableInputBudget,
    required this.compressionTriggerRatio,
    required this.totalEstimatedInputTokens,
    required this.totalWindowUsageRatio,
    required this.usableInputUsageRatio,
    required this.didCompactHistory,
    this.snapshotCoveredUntilTurnId,
    required this.recentCompletedTurnCount,
    required this.segments,
  });
}
