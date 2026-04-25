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

class ResearchWorkflowItem extends StatelessWidget {
  const ResearchWorkflowItem({
    super.key,
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    this.subtitle,
  });

  final String title;
  final String statusLabel;
  final Color statusColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: EdgeInsets.only(top: spacing.xs),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  SizedBox(height: spacing.xxs),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          height: 1.35,
                        ),
                  ),
                ],
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
        ],
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

String aggregateWorkflowStatusLabel(List<ToolWorkflowStep> steps) {
  if (steps.isEmpty) {
    return workflowStatusLabel(null);
  }
  final running = steps
      .where((step) => step.status == ToolWorkflowStepStatus.running)
      .length;
  if (running > 1) {
    return '$running 个执行中';
  }
  final awaiting = steps
      .where(
        (step) => step.status == ToolWorkflowStepStatus.awaitingConfirmation,
      )
      .length;
  if (awaiting > 1) {
    return '$awaiting 个待确认';
  }
  final failed = steps
      .where((step) => step.status == ToolWorkflowStepStatus.failed)
      .length;
  final completed = steps
      .where((step) => step.status == ToolWorkflowStepStatus.completed)
      .length;
  if (failed > 0 && completed > 0) {
    return '部分失败';
  }
  if (completed == steps.length && steps.length > 1) {
    return '全部完成';
  }
  return workflowStatusLabel(steps.last);
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

Color aggregateWorkflowStatusColor(
  BuildContext context,
  List<ToolWorkflowStep> steps,
) {
  if (steps.isEmpty) {
    return workflowStatusColor(context, null);
  }
  final hasRunning = steps.any(
    (step) => step.status == ToolWorkflowStepStatus.running,
  );
  if (hasRunning) {
    return workflowStatusColor(context, const ToolWorkflowStep(
      stepId: '',
      turnId: '',
      toolName: '',
      title: '',
      summary: '',
      status: ToolWorkflowStepStatus.running,
      requiresConfirmation: false,
    ));
  }
  final hasAwaiting = steps.any(
    (step) => step.status == ToolWorkflowStepStatus.awaitingConfirmation,
  );
  if (hasAwaiting) {
    return workflowStatusColor(context, const ToolWorkflowStep(
      stepId: '',
      turnId: '',
      toolName: '',
      title: '',
      summary: '',
      status: ToolWorkflowStepStatus.awaitingConfirmation,
      requiresConfirmation: false,
    ));
  }
  final hasFailed = steps.any(
    (step) => step.status == ToolWorkflowStepStatus.failed,
  );
  final hasCancelled = steps.any(
    (step) => step.status == ToolWorkflowStepStatus.cancelled,
  );
  if (hasFailed || hasCancelled) {
    return workflowStatusColor(context, const ToolWorkflowStep(
      stepId: '',
      turnId: '',
      toolName: '',
      title: '',
      summary: '',
      status: ToolWorkflowStepStatus.failed,
      requiresConfirmation: false,
    ));
  }
  return workflowStatusColor(context, steps.last);
}

Color resultStatusColor(BuildContext context, ToolResult result) {
  final colors = Theme.of(context).extension<AppColors>()!;
  return result.status == ToolExecutionStatus.success
      ? colors.workflowSuccess
      : colors.workflowWarning;
}
