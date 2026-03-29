import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
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
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.toolWorkflowSurface,
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.toolName,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                result.status == ToolExecutionStatus.success ? '完成' : '失败',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
