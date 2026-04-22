import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'edit_tool_result_card.dart';

class EditToolWorkflowCard extends StatelessWidget {
  const EditToolWorkflowCard({
    super.key,
    required this.steps,
    required this.isExpanded,
    this.onTap,
  });

  /// Ordered workflow history for the current edit block.
  final List<ToolWorkflowStep> steps;

  /// Shared timeline expansion state for the whole custom workflow card.
  final bool isExpanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final latestStep = steps.isEmpty ? null : steps.last;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '编辑文件',
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (steps.isNotEmpty)
                  Text(
                    '${steps.length} 步',
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (latestStep != null) ...[
              SizedBox(height: spacing.xs),
              Text(
                _buildOverview(latestStep),
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            SizedBox(height: spacing.xxs),
            Text(
              steps.length <= 1
                  ? _replaceModeLabel(latestStep)
                  : '这次编辑一共执行了 ${steps.length} 次替换动作',
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (isExpanded && steps.isNotEmpty) ...[
              SizedBox(height: spacing.sm),
              ...steps.asMap().entries.map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(bottom: spacing.xs),
                      child: _WorkflowStepDetailRow(
                        index: entry.key + 1,
                        title: _buildStepTitle(entry.value),
                        summary: _buildStepSummary(entry.value),
                        status: entry.value.status,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildOverview(ToolWorkflowStep latestStep) {
    final filePath = _filePathFor(latestStep);
    final prefix = filePath.isEmpty ? '最近一次编辑' : '最近一次编辑：$filePath';
    if (steps.length <= 1) {
      return filePath.isEmpty ? '准备编辑文件内容' : filePath;
    }
    return '$prefix，共发生 ${steps.length} 次编辑动作';
  }

  String _buildStepTitle(ToolWorkflowStep step) {
    final filePath = _filePathFor(step);
    final replaceMode = step.details['replace_all'] == true ? '全量替换' : '单次替换';
    if (filePath.isEmpty) {
      return replaceMode;
    }
    return '$replaceMode -> $filePath';
  }

  String _buildStepSummary(ToolWorkflowStep step) {
    final oldString = (step.details['old_string'] ?? '').toString().trim();
    final newString = (step.details['new_string'] ?? '').toString().trim();
    if (oldString.isEmpty && newString.isEmpty) {
      return step.summary;
    }
    return '把 "${_compactSnippet(oldString)}" 替换为 "${_compactSnippet(newString)}"';
  }

  String _replaceModeLabel(ToolWorkflowStep? step) {
    if (step == null) {
      return '替换首个匹配';
    }
    return step.details['replace_all'] == true ? '替换全部匹配' : '替换首个匹配';
  }

  String _compactSnippet(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 28) {
      return normalized;
    }
    return '${normalized.substring(0, 28)}...';
  }

  String _filePathFor(ToolWorkflowStep step) {
    return (step.details['file_path'] ?? '').toString();
  }
}

class EditToolUiRenderer extends ToolUiRenderer {
  const EditToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return EditToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return EditToolWorkflowCard(
      steps: steps,
      isExpanded: isExpanded,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'Edit';

  @override
  bool supportsWorkflowStep(String toolName) => toolName.trim() == 'Edit';
}

class _WorkflowStepDetailRow extends StatelessWidget {
  const _WorkflowStepDetailRow({
    required this.index,
    required this.title,
    required this.summary,
    required this.status,
  });

  final int index;
  final String title;
  final String summary;
  final ToolWorkflowStepStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '步骤 $index',
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: spacing.xs),
              Text(
                _statusLabel(status),
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxs),
          Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          SizedBox(height: spacing.xxs),
          Text(
            summary,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(ToolWorkflowStepStatus status) {
    switch (status) {
      case ToolWorkflowStepStatus.proposed:
        return '已提议';
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
    }
  }
}
