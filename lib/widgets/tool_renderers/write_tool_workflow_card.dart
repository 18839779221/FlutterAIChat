import 'package:flutter/material.dart';

import '../../models/chat/tool_phase_visibility.dart';
import '../../models/chat/tool_presentation_event.dart';
import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'file_change_preview.dart';
import 'write_tool_result_card.dart';

class WriteToolWorkflowCard extends StatelessWidget {
  const WriteToolWorkflowCard({
    super.key,
    required this.steps,
    required this.isExpanded,
    this.onTap,
  });

  /// Ordered workflow history for the current write block.
  final List<ToolWorkflowStep> steps;

  /// Shared timeline expansion state for the whole custom workflow card.
  final bool isExpanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final latestStep = steps.isEmpty ? null : steps.last;
    final hideOverview = isExpanded && steps.length == 1;
    final uniqueFiles =
        steps.map(_filePathFor).where((path) => path.isNotEmpty).toSet().length;

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
                    '写入文件',
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
            if (!hideOverview && latestStep != null) ...[
              SizedBox(height: spacing.xs),
              Text(
                _buildOverview(latestStep, uniqueFiles: uniqueFiles),
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            if (!hideOverview) ...[
              SizedBox(height: spacing.xxs),
              Text(
                steps.length <= 1
                    ? '新建或整文件覆盖'
                    : '这次写入一共进行了 ${steps.length} 次文件操作',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            if (isExpanded && steps.isNotEmpty) ...[
              SizedBox(height: spacing.sm),
              ...steps.asMap().entries.map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(bottom: spacing.xs),
                      child: _WorkflowStepDetailRow(
                        filePath: _filePathFor(entry.value),
                        contentPreview:
                            (entry.value.details['content'] ?? '').toString(),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildOverview(
    ToolWorkflowStep latestStep, {
    required int uniqueFiles,
  }) {
    final latestFile = _filePathFor(latestStep);
    if (steps.length <= 1) {
      return latestFile.isEmpty ? '准备写入内容' : latestFile;
    }
    if (latestFile.isEmpty) {
      return '最近一次写入后，当前共涉及 $uniqueFiles 个文件';
    }
    return '最近一次写入：$latestFile';
  }

  String _filePathFor(ToolWorkflowStep step) {
    return (step.details['file_path'] ?? '').toString();
  }
}

class WriteToolUiRenderer extends ToolUiRenderer {
  const WriteToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return WriteToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return WriteToolWorkflowCard(
      steps: steps,
      isExpanded: isExpanded,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'Write';

  @override
  bool supportsWorkflowStep(String toolName) => toolName.trim() == 'Write';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName.trim() == 'Write' &&
        phase == ToolPresentationEventPhase.proposed) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}

class _WorkflowStepDetailRow extends StatelessWidget {
  const _WorkflowStepDetailRow({
    required this.filePath,
    required this.contentPreview,
  });

  final String filePath;
  final String contentPreview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
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
          if (filePath.isNotEmpty)
            Text(
              filePath,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          if (contentPreview.isNotEmpty) ...[
            SizedBox(height: spacing.xs),
            FileChangePreview(
              oldContent: '',
              newContent: contentPreview,
              truncated: false,
              forceAdded: true,
            ),
          ],
        ],
      ),
    );
  }
}
