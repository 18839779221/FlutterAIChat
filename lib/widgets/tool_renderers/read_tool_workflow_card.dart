import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class ReadToolWorkflowCard extends StatelessWidget {
  const ReadToolWorkflowCard({
    super.key,
    required this.steps,
  });

  /// Ordered workflow history for the current read block.
  final List<ToolWorkflowStep> steps;

  @override
  Widget build(BuildContext context) {
    final latestStep = steps.isEmpty ? null : steps.last;
    return ReadToolCompactRow(
      filePath: latestStep == null ? '' : _filePathForStep(latestStep),
      statusLabel: latestStep == null ? '已提议' : _statusLabelForStep(latestStep),
      statusColor: _statusColorForStep(context, latestStep),
    );
  }

  static String _filePathForStep(ToolWorkflowStep step) {
    final fromDetails = (step.details['file_path'] ?? '').toString().trim();
    if (fromDetails.isNotEmpty) {
      return fromDetails;
    }
    return step.summary.trim();
  }

  static String _statusLabelForStep(ToolWorkflowStep step) {
    switch (step.status) {
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

  static Color _statusColorForStep(
    BuildContext context,
    ToolWorkflowStep? step,
  ) {
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
}

class ReadToolResultCard extends StatelessWidget {
  const ReadToolResultCard({
    super.key,
    required this.result,
  });

  /// Final read outcome projected from the tool result payload.
  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    return ReadToolCompactRow(
      filePath: _filePathForResult(result),
      statusLabel: result.statusLabel,
      statusColor: _statusColorForResult(context, result),
    );
  }

  static String _filePathForResult(ToolResult result) {
    final filePath = (result.data['filePath'] ?? '').toString().trim();
    if (filePath.isNotEmpty) {
      return filePath;
    }
    return result.summary.trim();
  }

  static Color _statusColorForResult(
    BuildContext context,
    ToolResult result,
  ) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return result.status == ToolExecutionStatus.success
        ? colors.workflowSuccess
        : colors.workflowWarning;
  }
}

class ReadToolCompactRow extends StatelessWidget {
  const ReadToolCompactRow({
    super.key,
    required this.filePath,
    required this.statusLabel,
    required this.statusColor,
  });

  /// Relative sandbox path for the file the tool touched.
  final String filePath;

  /// Compact state label shown on the right side of the row.
  final String statusLabel;

  /// Shared semantic color derived from the tool execution state.
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final display = _ReadPathDisplay.fromPath(filePath);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm + spacing.xxs,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.structuredSurface.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(radius.sm + 1),
      ),
      child: Row(
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
                  '读取',
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                SizedBox(width: spacing.xs),
                if (display.directory.isNotEmpty) ...[
                  Flexible(
                    fit: FlexFit.tight,
                    child: Text(
                      display.directory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ),
                  Text(
                    '/',
                    style: TextStyle(
                      color: colors.secondaryText.withValues(alpha: 0.9),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(width: spacing.xxs),
                ],
                Flexible(
                  flex: 2,
                  fit: FlexFit.tight,
                  child: Text(
                    display.fileName,
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
        ],
      ),
    );
  }
}

class ReadToolUiRenderer extends ToolUiRenderer {
  const ReadToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return ReadToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return ReadToolWorkflowCard(steps: steps);
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'Read';

  @override
  bool supportsWorkflowStep(String toolName) => toolName.trim() == 'Read';
}

class _ReadPathDisplay {
  const _ReadPathDisplay({
    required this.directory,
    required this.fileName,
  });

  final String directory;
  final String fileName;

  static _ReadPathDisplay fromPath(String rawPath) {
    final normalized = rawPath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) {
      return const _ReadPathDisplay(directory: '', fileName: '已读取文件');
    }

    final baseName = path.basename(normalized).trim();
    if (baseName.isEmpty || baseName == normalized) {
      return _ReadPathDisplay(
        directory: '',
        fileName: _compactFileName(normalized),
      );
    }

    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    final directorySegments = segments.isEmpty
        ? const <String>[]
        : segments.sublist(0, segments.length - 1);

    return _ReadPathDisplay(
      directory: _compactDirectory(directorySegments),
      fileName: _compactFileName(baseName),
    );
  }

  static String _compactDirectory(List<String> segments) {
    if (segments.isEmpty) {
      return '';
    }
    if (segments.length <= 3) {
      return segments.join('/');
    }
    return '${segments.first}/${segments[1]}/.../${segments.last}';
  }

  static String _compactFileName(String value) {
    if (value.length <= 36) {
      return value;
    }

    final dotIndex = value.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == value.length - 1) {
      return '${value.substring(0, 16)}...${value.substring(value.length - 12)}';
    }

    final extension = value.substring(dotIndex);
    final base = value.substring(0, dotIndex);
    final suffixBudget = extension.length + 7;
    final prefixBudget = 36 - 3 - suffixBudget;
    if (prefixBudget <= 6 || base.length <= prefixBudget + 4) {
      return '${value.substring(0, 16)}...${value.substring(value.length - 12)}';
    }
    return '${base.substring(0, prefixBudget)}...${base.substring(base.length - 7)}$extension';
  }
}
