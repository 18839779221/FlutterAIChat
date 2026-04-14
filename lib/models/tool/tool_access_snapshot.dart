import 'tool_definition.dart';
import 'tool_policy.dart';

/// Shared runtime/planner view of one tool's current access policy.
class ToolAccessSnapshot {
  /// Stable tool definition referenced by planner exposure and runtime.
  final ToolDefinition definition;

  /// Concrete execution decision enforced by the runtime.
  final ToolPolicyDecision executionDecision;

  /// Stable serialized label used in prompts, traces, and payloads.
  final String executionPolicyLabel;

  /// Whether the tool should be visible to the planner at all.
  final bool isVisibleToPlanner;

  const ToolAccessSnapshot({
    required this.definition,
    required this.executionDecision,
    required this.executionPolicyLabel,
    required this.isVisibleToPlanner,
  });

  factory ToolAccessSnapshot.autoRun({
    required ToolDefinition definition,
  }) {
    return ToolAccessSnapshot.fromDecision(
      definition: definition,
      executionDecision: ToolPolicyDecision.autoRun,
    );
  }

  factory ToolAccessSnapshot.fromLegacyDefinition({
    required ToolDefinition definition,
    bool isBlocked = false,
  }) {
    final executionDecision = isBlocked
        ? ToolPolicyDecision.blocked
        : (definition.requiresConfirmation
            ? ToolPolicyDecision.requireConfirmation
            : ToolPolicyDecision.autoRun);
    final executionPolicyLabel = switch (executionDecision) {
      ToolPolicyDecision.autoRun => 'auto_run',
      ToolPolicyDecision.requireConfirmation => 'require_confirmation',
      ToolPolicyDecision.blocked => 'blocked',
    };
    return ToolAccessSnapshot(
      definition: definition,
      executionDecision: executionDecision,
      executionPolicyLabel: executionPolicyLabel,
      isVisibleToPlanner: !isBlocked,
    );
  }

  factory ToolAccessSnapshot.fromDecision({
    required ToolDefinition definition,
    required ToolPolicyDecision executionDecision,
  }) {
    final executionPolicyLabel = switch (executionDecision) {
      ToolPolicyDecision.autoRun => 'auto_run',
      ToolPolicyDecision.requireConfirmation => 'require_confirmation',
      ToolPolicyDecision.blocked => 'blocked',
    };
    return ToolAccessSnapshot(
      definition: definition,
      executionDecision: executionDecision,
      executionPolicyLabel: executionPolicyLabel,
      isVisibleToPlanner: executionDecision != ToolPolicyDecision.blocked,
    );
  }

  /// Stable serialized snapshot shared by planner/runtime/UI payloads.
  Map<String, dynamic> toJson() {
    return {
      'toolName': definition.name,
      'executionDecision': executionDecision.name,
      'executionPolicy': executionPolicyLabel,
      'isVisibleToPlanner': isVisibleToPlanner,
    };
  }
}
