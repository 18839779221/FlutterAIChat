/// Stable segment kinds used by the context window UI.
enum ContextWindowSegmentType {
  systemPrompt,
  runtimeUserContext,
  historySummary,
  recentCompletedTurns,
  currentTurnTranscript,
  reservedOutput,
  reasoningReserve,
  safetyMargin,
  freeHeadroom,
}

class ContextWindowSegment {
  /// Stable segment type so UI can map colors and grouping consistently.
  final ContextWindowSegmentType type;

  /// User-facing short label shown in the detail sheet.
  final String label;

  /// Locally estimated token cost for this segment.
  final int estimatedTokens;

  /// Share of the full provider-advertised context window.
  final double shareOfTotalWindow;

  /// Share of the planner-usable input budget.
  final double shareOfUsableInput;

  /// Whether this segment is actually visible to the planner.
  final bool isPlannerVisible;

  /// Optional structured explanation such as covered turn ids or item counts.
  final Map<String, Object?> details;

  const ContextWindowSegment({
    required this.type,
    required this.label,
    required this.estimatedTokens,
    required this.shareOfTotalWindow,
    required this.shareOfUsableInput,
    required this.isPlannerVisible,
    this.details = const {},
  });
}
