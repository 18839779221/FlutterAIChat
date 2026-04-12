import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Foldable workflow card that only expands the active step by default.
class ToolWorkflowCard extends StatelessWidget {
  final String title;
  final List<ToolWorkflowStep> steps;
  final String? expandedStepId;
  final ValueChanged<String>? onStepTapped;
  final VoidCallback? onContinue;
  final VoidCallback? onCancel;
  final VoidCallback? onContinueAndTrust;

  const ToolWorkflowCard({
    super.key,
    required this.title,
    required this.steps,
    this.expandedStepId,
    this.onStepTapped,
    this.onContinue,
    this.onCancel,
    this.onContinueAndTrust,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        spacing.md + spacing.xs,
        spacing.sm + spacing.xs,
        spacing.md + spacing.xs,
        spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(radius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.24,
            ),
          ),
          SizedBox(height: spacing.sm),
          ...steps.map((step) {
            final expanded = step.stepId == expandedStepId;
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.xs + spacing.xxs),
              child: InkWell(
                onTap: onStepTapped == null
                    ? null
                    : () => onStepTapped!(step.stepId),
                borderRadius: BorderRadius.circular(radius.md),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.all(spacing.sm),
                  decoration: BoxDecoration(
                    color: expanded
                        ? colors.assistantSurface.withValues(alpha: 0.96)
                        : colors.chatBackground.withValues(alpha: 0.56),
                    borderRadius: BorderRadius.circular(radius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _statusColor(colors, step.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: spacing.sm),
                          Expanded(
                            child: Text(
                              step.title.isEmpty ? step.toolName : step.title,
                              style: TextStyle(
                                color: colors.primaryText,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.xs,
                              vertical: spacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                colors,
                                step.status,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(radius.pill),
                            ),
                            child: Text(
                              _statusLabel(step.status),
                              style: TextStyle(
                                color: _statusColor(colors, step.status),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        step.summary,
                        maxLines: expanded ? null : 1,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 11.5,
                          height: 1.42,
                        ),
                      ),
                      if (expanded && step.requiresConfirmation) ...[
                        SizedBox(height: spacing.sm),
                        Wrap(
                          spacing: spacing.xs,
                          runSpacing: spacing.xs,
                          children: [
                            FilledButton(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(radius.pill),
                                ),
                              ),
                              onPressed: onContinue,
                              child: const Text('继续'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(radius.pill),
                                ),
                              ),
                              onPressed: onCancel,
                              child: const Text('取消'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(radius.pill),
                                ),
                              ),
                              onPressed: onContinueAndTrust,
                              child: const Text('继续，以后不再确认'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _statusLabel(ToolWorkflowStepStatus status) {
    switch (status) {
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
        return '已提议';
    }
  }

  Color _statusColor(AppColors colors, ToolWorkflowStepStatus status) {
    switch (status) {
      case ToolWorkflowStepStatus.completed:
        return colors.workflowSuccess;
      case ToolWorkflowStepStatus.failed:
      case ToolWorkflowStepStatus.cancelled:
        return colors.workflowWarning;
      case ToolWorkflowStepStatus.awaitingConfirmation:
      case ToolWorkflowStepStatus.running:
      case ToolWorkflowStepStatus.proposed:
        return colors.workflowRunning;
    }
  }
}
