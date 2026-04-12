class AgentLoopLimits {
  final int maxIterations;
  final int maxToolCallsPerTurn;
  final int maxConsecutiveFailures;
  final Duration maxDuration;

  const AgentLoopLimits({
    this.maxIterations = 6,
    this.maxToolCallsPerTurn = 6,
    this.maxConsecutiveFailures = 2,
    this.maxDuration = const Duration(minutes: 2),
  });
}
