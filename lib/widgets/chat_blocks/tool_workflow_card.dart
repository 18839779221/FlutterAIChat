import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/services/tool_card_presentation_mapper.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';

import 'tool_inline_step_row.dart';
import '../tool_renderers/tool_running_effects.dart';

/// Foldable workflow card that only expands the active step by default.
class ToolWorkflowCard extends StatelessWidget {
  final String title;
  final List<ToolWorkflowStep> steps;
  final String? expandedStepId;
  final ValueChanged<String>? onStepTapped;

  const ToolWorkflowCard({
    super.key,
    required this.title,
    required this.steps,
    this.expandedStepId,
    this.onStepTapped,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
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
        color: colors.structuredSurface,
        borderRadius: BorderRadius.circular(radius.md + 2),
        border: Border.all(color: colors.divider, width: 1),
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
            final presentation = ToolCardPresentationMapper.mapStep(step);
            final usesInlineHistory = !expanded &&
                presentation.variant == ToolCardPresentationVariant.inlineStep &&
                step.isContextGatheringTool;
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.xs + spacing.xxs),
              child: InkWell(
                onTap: onStepTapped == null
                    ? null
                    : () => onStepTapped!(step.stepId),
                borderRadius: BorderRadius.circular(radius.md),
                child: usesInlineHistory
                    ? ToolInlineStepRow(model: presentation)
                    : RunningSweepSurface(
                        isRunning: step.status == ToolWorkflowStepStatus.running,
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
                                  RunningStatusDot(
                                    color: _statusColor(colors, step.status),
                                    isRunning:
                                        step.status == ToolWorkflowStepStatus.running,
                                    size: 8,
                                  ),
                                  SizedBox(width: spacing.sm),
                                  Expanded(
                                    child: Text(
                                      step.title.isEmpty
                                          ? step.toolName
                                          : step.title,
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
                                      borderRadius:
                                          BorderRadius.circular(radius.pill),
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
                              if (expanded && _showsConfirmationActions(step))
                                SizedBox(height: spacing.xxs),
                            ],
                          ),
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

  bool _showsConfirmationActions(ToolWorkflowStep step) {
    return step.showsConfirmationActions;
  }

  Color _statusColor(AppThemeSpec colors, ToolWorkflowStepStatus status) {
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
