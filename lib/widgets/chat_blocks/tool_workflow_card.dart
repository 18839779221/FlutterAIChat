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
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.toolWorkflowSurface,
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: spacing.xs),
          ...steps.map((step) {
            final expanded = step.stepId == expandedStepId;
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.xs),
              child: InkWell(
                onTap: onStepTapped == null ? null : () => onStepTapped!(step.stepId),
                child: Container(
                  padding: EdgeInsets.all(spacing.sm),
                  decoration: BoxDecoration(
                    color: expanded ? colors.assistantSurface : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(radius.sm),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              step.toolName,
                              style: TextStyle(
                                color: colors.primaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _statusLabel(step.status),
                            style: TextStyle(
                              color: _statusColor(colors, step.status),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        step.summary,
                        maxLines: expanded ? null : 1,
                        overflow:
                            expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      if (expanded && step.requiresConfirmation) ...[
                        SizedBox(height: spacing.xs),
                        Wrap(
                          spacing: spacing.xs,
                          runSpacing: spacing.xs,
                          children: [
                            FilledButton(
                              onPressed: onContinue,
                              child: const Text('继续'),
                            ),
                            OutlinedButton(
                              onPressed: onCancel,
                              child: const Text('取消'),
                            ),
                            OutlinedButton(
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
