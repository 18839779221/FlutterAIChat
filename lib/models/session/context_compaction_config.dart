/// Tunable thresholds controlling when and how session history compacts.
class ContextCompactionConfig {
  /// Keep this many tokens free before auto-compaction is allowed to trigger.
  final int autoCompactBufferTokens;

  /// Target ratio for summary + recent completed turns after compaction.
  final double postCompressionHistoryRatio;

  /// Default maximum number of recent completed turns to retain in raw form.
  final int defaultRecentCompletedTurns;

  /// Maximum share of usable input budget allowed for recent raw turns.
  final double recentTurnsMaxRatio;

  /// Minimum number of completed turns to keep even under heavy pressure.
  final int minRecentCompletedTurns;

  const ContextCompactionConfig({
    this.autoCompactBufferTokens = 13000,
    this.postCompressionHistoryRatio = 0.15,
    this.defaultRecentCompletedTurns = 6,
    this.recentTurnsMaxRatio = 0.10,
    this.minRecentCompletedTurns = 1,
  });
}
