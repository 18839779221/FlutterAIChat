/// Declares provider/runtime capabilities that affect common orchestration
/// decisions in `ConfigurableHttpLLM`.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.supportsPlannerStreaming,
    required this.supportsParallelToolCalls,
  });

  /// Whether planner requests should use the runtime streaming path when
  /// available for this provider contract.
  final bool supportsPlannerStreaming;

  /// Whether this provider contract can advertise/use parallel tool calls in
  /// outbound planner requests.
  final bool supportsParallelToolCalls;
}
