import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/tools/core/tool_display_names.dart';
import 'package:flutter/material.dart';

/// Collapsed one-row-ish summary surface for completed tool work.
class ToolResultSummaryRow extends StatelessWidget {
  final ToolResult result;

  const ToolResultSummaryRow({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final statusColor = result.status == ToolExecutionStatus.success
        ? colors.workflowSuccess
        : colors.workflowWarning;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.xs + spacing.xxs,
        vertical: spacing.xs - 1,
      ),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(radius.sm + 1),
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
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  resolveToolDisplayName(result.toolName),
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
                  result.status == ToolExecutionStatus.success ? '完成' : '失败',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxs),
          Text(
            result.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 10.5,
              height: 1.28,
            ),
          ),
        ],
      ),
    );
  }
}
