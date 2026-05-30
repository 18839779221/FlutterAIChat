/// Coarse single-line phase shown in the primary running status surface.
enum ActiveTurnStatusPhase {
  planning,
  awaitingConfirmation,
  executingTool,
  streamingResponse,
}

/// Declares which formal signal produced the active status presentation.
enum ActiveTurnStatusSourceKind {
  confirmation,
  toolEvent,
  runtimePreview,
  sendPhaseFallback,
}

/// One unified user-facing active-turn status consumed by both timeline and
/// floating status hosts.
class ActiveTurnStatusPresentation {
  const ActiveTurnStatusPresentation({
    required this.phase,
    required this.text,
    required this.turnId,
    required this.sourceKind,
    required this.allowFloating,
    this.sourceMessageId,
    this.toolName,
  });

  /// Coarse lifecycle stage currently visible to the user.
  final ActiveTurnStatusPhase phase;

  /// Single primary line of user-facing status copy.
  final String text;

  /// Stable turn identity for correlating the status with timeline content.
  final String turnId;

  /// Optional transcript message id that anchors the status in the timeline.
  final int? sourceMessageId;

  /// Tool name when the active status is driven by a tool-related phase.
  final String? toolName;

  /// Formal source category that produced this presentation.
  final ActiveTurnStatusSourceKind sourceKind;

  /// Whether this status is allowed to move into a floating host.
  final bool allowFloating;
}
