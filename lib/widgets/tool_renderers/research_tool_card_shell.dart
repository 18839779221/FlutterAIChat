import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/tool/tool_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class ResearchToolCardShell extends StatelessWidget {
  const ResearchToolCardShell({
    super.key,
    required this.actionLabel,
    required this.primaryText,
    required this.statusLabel,
    required this.statusColor,
    this.body,
    this.footerHint,
    this.expanded = false,
    this.onTap,
    this.expandedChild,
  });

  final String actionLabel;
  final String primaryText;
  final String statusLabel;
  final Color statusColor;
  final Widget? body;
  final String? footerHint;
  final bool expanded;
  final VoidCallback? onTap;
  final Widget? expandedChild;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final hasExpandedChild = expandedChild != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm + spacing.xxs,
          vertical: spacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.structuredSurface
              .withValues(alpha: expanded ? 0.46 : 0.34),
          borderRadius: BorderRadius.circular(radius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.88),
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        actionLabel,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      SizedBox(width: spacing.xs),
                      Expanded(
                        child: Text(
                          primaryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.sm),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.xs,
                    vertical: spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(radius.pill),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasExpandedChild) ...[
                  SizedBox(width: spacing.xs),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                ],
              ],
            ),
            if (expanded && expandedChild != null) ...[
              if (body != null) ...[
                SizedBox(height: spacing.sm),
                body!,
              ],
              SizedBox(height: spacing.sm),
              Container(
                width: double.infinity,
                height: 1,
                color: colors.chatBackground.withValues(alpha: 0.58),
              ),
              SizedBox(height: spacing.sm),
              expandedChild!,
            ] else if (body != null) ...[
              SizedBox(height: spacing.sm),
              body!,
            ],
            if (!expanded &&
                footerHint != null &&
                footerHint!.trim().isNotEmpty &&
                onTap != null) ...[
              SizedBox(height: spacing.xs),
              Text(
                footerHint!,
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String workflowStatusLabel(ToolWorkflowStep? step) {
  switch (step?.status) {
    case ToolWorkflowStepStatus.awaitingConfirmation:
      return '待确认';
    case ToolWorkflowStepStatus.running:
      return '执行中';
    case ToolWorkflowStepStatus.completed:
      return '完成';
    case ToolWorkflowStepStatus.failed:
      return '失败';
    case ToolWorkflowStepStatus.cancelled:
      return '已取消';
    case ToolWorkflowStepStatus.proposed:
    case null:
      return '已提议';
  }
}

Color workflowStatusColor(BuildContext context, ToolWorkflowStep? step) {
  final colors = Theme.of(context).extension<AppColors>()!;
  switch (step?.status) {
    case ToolWorkflowStepStatus.completed:
      return colors.workflowSuccess;
    case ToolWorkflowStepStatus.failed:
    case ToolWorkflowStepStatus.cancelled:
      return colors.workflowWarning;
    case ToolWorkflowStepStatus.awaitingConfirmation:
    case ToolWorkflowStepStatus.running:
    case ToolWorkflowStepStatus.proposed:
    case null:
      return colors.workflowRunning;
  }
}

Color resultStatusColor(BuildContext context, ToolResult result) {
  final colors = Theme.of(context).extension<AppColors>()!;
  return result.status == ToolExecutionStatus.success
      ? colors.workflowSuccess
      : colors.workflowWarning;
}
