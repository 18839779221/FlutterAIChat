class AgentLoopLimits {
  /// Maximum planner rounds allowed for one turn before forcing a stop.
  final int? maxIterations;

  /// Maximum completed tool executions allowed in a single turn.
  final int? maxToolCallsPerTurn;

  /// Maximum number of consecutive failed tool executions before aborting.
  final int? maxConsecutiveFailures;

  /// Maximum wall-clock duration allowed for a single turn.
  final Duration? maxDuration;

  const AgentLoopLimits({
    this.maxIterations,
    this.maxToolCallsPerTurn,
    this.maxConsecutiveFailures,
    this.maxDuration,
  });
}
