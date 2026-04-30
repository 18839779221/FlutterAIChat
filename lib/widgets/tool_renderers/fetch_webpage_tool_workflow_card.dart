import 'package:flutter/material.dart';

import '../../models/chat/tool_phase_visibility.dart';
import '../../models/chat/tool_presentation_event.dart';
import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import 'fetch_webpage_tool_result_card.dart';
import 'research_tool_card_shell.dart';

class FetchWebpageToolWorkflowCard extends StatelessWidget {
  const FetchWebpageToolWorkflowCard({
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
    final url = (details['url'] ?? '').toString();
    final host = _hostFromUrl(url);
    final prompt = (details['prompt'] ?? '').toString().trim();

    return ResearchToolCardShell(
      actionLabel: '读取网页',
      primaryText: '阅读网页 · ${host.isEmpty ? '网页内容' : host}',
      statusLabel: workflowStatusLabel(step),
      statusColor: workflowStatusColor(context, step),
      isRunning: step?.status == ToolWorkflowStepStatus.running,
      body: prompt.isEmpty
          ? null
          : Text(
              prompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
      onTap: onTap,
    );
  }

  String _hostFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.trim().isEmpty) {
      return url.trim();
    }
    return parsed.host.trim();
  }
}

class FetchWebpageToolUiRenderer extends ToolUiRenderer {
  const FetchWebpageToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return FetchWebpageToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return FetchWebpageToolWorkflowCard(
      steps: steps,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'fetch_webpage';

  @override
  bool supportsWorkflowStep(String toolName) =>
      toolName.trim() == 'fetch_webpage';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName.trim() == 'fetch_webpage' &&
        phase == ToolPresentationEventPhase.proposed) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}
