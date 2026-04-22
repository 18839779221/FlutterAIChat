import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
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
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final step = steps.isEmpty ? null : steps.last;
    final details = step?.details ?? const <String, dynamic>{};
    final query = (details['query'] ?? '').toString();
    final maxResults = details['maxResults'] ?? details['num_results'];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius.md + 2),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: colors.structuredSurface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(radius.md + 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '联网搜索',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xs),
            if (query.isNotEmpty)
              Text(
                query,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (maxResults is num || maxResults is String) ...[
              SizedBox(height: spacing.xxs),
              Text(
                '最多返回 $maxResults 条结果',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
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
    if (result.status == ToolExecutionStatus.failure) {
      return null;
    }
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
