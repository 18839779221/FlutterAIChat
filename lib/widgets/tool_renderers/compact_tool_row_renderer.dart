import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'tool_running_effects.dart';

typedef CompactToolRowWorkflowMapper = CompactToolRowModel Function(
    List<ToolWorkflowStep> steps);
typedef CompactToolRowResultMapper = CompactToolRowModel Function(
  ToolResult result,
);

class CompactToolRowModel {
  const CompactToolRowModel({
    required this.actionLabel,
    required this.primaryText,
    required this.statusLabel,
    required this.statusColor,
    this.isRunning = false,
  });

  /// Low-noise verb that tells the user what kind of tool action happened.
  final String actionLabel;

  /// Core target text shown after the action label.
  final String primaryText;

  /// Compact state label shown on the right side of the row.
  final String statusLabel;

  /// Shared semantic color derived from the tool execution state.
  final Color statusColor;

  /// Whether the row represents a running workflow item.
  final bool isRunning;
}

class CompactToolRow extends StatelessWidget {
  const CompactToolRow({
    super.key,
    required this.model,
  });

  final CompactToolRowModel model;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return SubtleRunningBreathingSurface(
      isRunning: model.isRunning,
      baseColor: colors.structuredSurface.withValues(alpha: 0.34),
      borderRadius: BorderRadius.circular(radius.sm + 1),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm + spacing.xxs,
          vertical: spacing.xs,
        ),
        child: Row(
          children: [
            RunningStatusDot(
              color: model.statusColor,
              isRunning: model.isRunning,
              size: 7,
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Row(
                children: [
                  Text(
                    model.actionLabel,
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
                      model.primaryText,
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
                color: model.statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(radius.pill),
              ),
              child: Text(
                model.statusLabel,
                style: TextStyle(
                  color: model.statusColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompactToolRowToolUiRenderer extends ToolUiRenderer {
  const CompactToolRowToolUiRenderer({
    required this.toolName,
    required this.workflowMapper,
    required this.resultMapper,
  });

  final String toolName;
  final CompactToolRowWorkflowMapper workflowMapper;
  final CompactToolRowResultMapper resultMapper;

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return CompactToolRow(model: resultMapper(result));
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return CompactToolRow(model: workflowMapper(steps));
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == this.toolName;

  @override
  bool supportsWorkflowStep(String toolName) =>
      toolName.trim() == this.toolName;
}
