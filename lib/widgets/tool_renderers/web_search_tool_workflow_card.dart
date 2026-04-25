import 'package:flutter/material.dart';

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
    final query = (details['query'] ?? '').toString();
    final maxResults = details['maxResults'] ?? details['num_results'];

    return ResearchToolCardShell(
      actionLabel: '联网搜索',
      primaryText: _buildPrimaryText(query: query, maxResults: maxResults),
      statusLabel: workflowStatusLabel(step),
      statusColor: workflowStatusColor(context, step),
      onTap: onTap,
    );
  }

  String _buildPrimaryText({
    required String query,
    required Object? maxResults,
  }) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return maxResults == null ? '搜索中' : '最多返回 $maxResults 条结果';
    }
    if (maxResults is num || maxResults is String) {
      return '$trimmedQuery · 最多 $maxResults 条';
    }
    return trimmedQuery;
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
}
