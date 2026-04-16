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
  static const String requireConfirmationPolicy = 'require_confirmation';
  static const String executionPolicyKey = 'executionPolicy';

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

  /// Stable policy label projected from runtime tool access.
  final String? executionPolicy;

  /// Shared access snapshot projected from runtime payload.
  final Map<String, dynamic>? toolAccess;

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
    this.executionPolicy,
    this.toolAccess,
    this.details = const {},
  });

  /// Effective policy label projected from the shared tool access snapshot.
  String? get resolvedExecutionPolicy {
    final snapshotPolicy = toolAccess?[executionPolicyKey];
    if (snapshotPolicy is String && snapshotPolicy.trim().isNotEmpty) {
      return snapshotPolicy.trim();
    }
    if (executionPolicy == null || executionPolicy!.trim().isEmpty) {
      return null;
    }
    return executionPolicy!.trim();
  }

  /// Whether the UI should expose confirmation actions for this step.
  bool get showsConfirmationActions {
    if (requiresConfirmation) {
      return true;
    }
    return resolvedExecutionPolicy == requireConfirmationPolicy;
  }

  /// Whether this tool step belongs to the low-noise context-gathering family.
  bool get isContextGatheringTool {
    switch (toolName.trim()) {
      case 'search_chat_history':
      case 'web_search':
      case 'fetch_webpage':
      case 'LS':
      case 'Glob':
      case 'Grep':
      case 'Read':
        return true;
      default:
        return false;
    }
  }
}
