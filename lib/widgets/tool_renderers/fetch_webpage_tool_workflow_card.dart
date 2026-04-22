import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'fetch_webpage_tool_result_card.dart';

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
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final step = steps.isEmpty ? null : steps.last;
    final details = step?.details ?? const <String, dynamic>{};
    final url = (details['url'] ?? '').toString();
    final extractMode = (details['extractMode'] ?? '').toString();

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
              '读取网页',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xs),
            if (url.isNotEmpty)
              Text(
                url,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (extractMode.isNotEmpty) ...[
              SizedBox(height: spacing.xxs),
              Text(
                '提取模式：$extractMode',
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

class FetchWebpageToolUiRenderer extends ToolUiRenderer {
  const FetchWebpageToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    if (result.status == ToolExecutionStatus.failure) {
      return null;
    }
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
}
