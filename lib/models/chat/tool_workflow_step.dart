/// UI-facing workflow step status used by the foldable tool workflow card.
enum ToolWorkflowStepStatus {
  proposed,
  awaitingConfirmation,
  running,
  completed,
  failed,
  cancelled,
}

/// Represents one visible step in a tool workflow timeline.
class ToolWorkflowStep {
  /// Stable identifier within the current assistant turn.
  final String stepId;

  /// Assistant turn that owns this step.
  final String turnId;

  /// Registered tool name.
  final String toolName;

  /// User-facing title shown in the workflow UI.
  final String title;

  /// Compact summary for collapsed rows or overview text.
  final String summary;

  /// Current step status.
  final ToolWorkflowStepStatus status;

  /// Whether this step requires explicit confirmation from the user.
  final bool requiresConfirmation;

  /// Optional structured details for future workflow rendering.
  final Map<String, dynamic> details;

  const ToolWorkflowStep({
    required this.stepId,
    required this.turnId,
    required this.toolName,
    required this.title,
    required this.summary,
    required this.status,
    required this.requiresConfirmation,
    this.details = const {},
  });
}
