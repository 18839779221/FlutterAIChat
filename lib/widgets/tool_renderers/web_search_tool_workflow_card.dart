import 'package:flutter/material.dart';

import '../../models/chat/tool_phase_visibility.dart';
import '../../models/chat/tool_presentation_event.dart';
import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import 'research_tool_card_shell.dart';
import 'web_search_tool_result_card.dart';

class WebSearchToolWorkflowCard extends StatelessWidget {
  const WebSearchToolWorkflowCard({
    super.key,
    required this.steps,
    this.onTap,
  });

  final List<ToolWorkflowStep> steps;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final step = steps.isEmpty ? null : steps.last;
    final details = step?.details ?? const <String, dynamic>{};
    final query = (details['query'] ?? '').toString().trim();

    return ResearchToolCardShell(
      actionLabel: '联网搜索',
      primaryText: query.isEmpty ? '搜索中' : query,
      statusLabel: workflowStatusLabel(step),
      statusColor: workflowStatusColor(context, step),
      isRunning: step?.status == ToolWorkflowStepStatus.running,
      onTap: onTap,
    );
  }
}

class WebSearchToolUiRenderer extends ToolUiRenderer {
  const WebSearchToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return WebSearchToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return WebSearchToolWorkflowCard(
      steps: steps,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'web_search';

  @override
  bool supportsWorkflowStep(String toolName) => toolName.trim() == 'web_search';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName.trim() == 'web_search' &&
        phase == ToolPresentationEventPhase.proposed) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}
