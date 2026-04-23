/// Carries runtime-only context that should be injected as a synthetic user
/// reminder, rather than being persisted as session history.
class RuntimeUserContextSnapshot {
  /// Human-readable current-date text shown to the model.
  final String currentDateText;

  /// Project-level AGENTS.md-derived guidance for the current runtime.
  final String agentsMdText;

  /// Optional extra runtime sections that may be appended later.
  final List<String> additionalSections;

  const RuntimeUserContextSnapshot({
    required this.currentDateText,
    required this.agentsMdText,
    this.additionalSections = const [],
  });
}
