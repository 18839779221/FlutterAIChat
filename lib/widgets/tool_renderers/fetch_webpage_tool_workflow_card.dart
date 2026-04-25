import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_spacing.dart';
import 'fetch_webpage_tool_result_card.dart';
import 'research_tool_card_shell.dart';

class FetchWebpageToolWorkflowCard extends StatelessWidget {
  const FetchWebpageToolWorkflowCard({
    super.key,
    required this.steps,
    required this.expanded,
    this.onTap,
  });

  final List<ToolWorkflowStep> steps;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final summary = _summarizeSteps(steps);
    final bodyText = _buildCollapsedBodyText(summary);
    final canExpand = summary.totalCount > 1 || summary.hasDetailContent;

    return ResearchToolCardShell(
      actionLabel: '读取网页',
      primaryText: _buildPrimaryText(summary),
      statusLabel: aggregateWorkflowStatusLabel(steps),
      statusColor: aggregateWorkflowStatusColor(context, steps),
      expanded: expanded,
      footerHint: canExpand
          ? summary.totalCount > 1
              ? '点击查看本批网页状态'
              : '查看详情'
          : null,
      body: bodyText == null
          ? null
          : Text(
              bodyText,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
            ),
      onTap: onTap,
      expandedChild: canExpand ? _buildExpandedContent(summary) : null,
    );
  }

  Widget _buildExpandedContent(_FetchWorkflowSummary summary) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final spacing = theme.extension<AppSpacing>()!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.totalCount > 1
                  ? '本批共 ${summary.totalCount} 个网页'
                  : '网页详情',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.sm),
            for (var index = 0; index < summary.items.length; index++) ...[
              ResearchWorkflowItem(
                title: summary.items[index].title,
                subtitle: summary.items[index].subtitle,
                statusLabel: workflowStatusLabel(summary.items[index].step),
                statusColor:
                    workflowStatusColor(context, summary.items[index].step),
              ),
              if (index != summary.items.length - 1) SizedBox(height: spacing.xs),
            ],
          ],
        );
      },
    );
  }

  String _buildPrimaryText(_FetchWorkflowSummary summary) {
    if (summary.totalCount <= 1) {
      final item = summary.items.isEmpty ? null : summary.items.first;
      return '阅读网页 · ${item == null ? '网页内容' : item.title}';
    }
    if (summary.runningCount > 1) {
      return '并行读取 ${summary.runningCount} 个网页';
    }
    if (summary.completedCount == summary.totalCount) {
      return '已读取 ${summary.totalCount} 个网页';
    }
    return '读取网页 · ${summary.totalCount} 个目标';
  }

  String? _buildCollapsedBodyText(_FetchWorkflowSummary summary) {
    if (summary.totalCount <= 1) {
      final subtitle = summary.items.isEmpty ? '' : summary.items.first.subtitle;
      final trimmed = subtitle.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final previewItems = summary.items.take(2).toList(growable: false);
    if (previewItems.isEmpty) {
      return null;
    }
    final lines = previewItems.map((item) => item.title).toList(growable: false);
    final remaining = summary.totalCount - previewItems.length;
    if (remaining > 0) {
      lines.add('以及另外 $remaining 个网页');
    }
    return lines.join('\n');
  }

  _FetchWorkflowSummary _summarizeSteps(List<ToolWorkflowStep> steps) {
    final items = steps.map(_toItem).toList(growable: false);
    final runningCount = steps
        .where((step) => step.status == ToolWorkflowStepStatus.running)
        .length;
    final completedCount = steps
        .where((step) => step.status == ToolWorkflowStepStatus.completed)
        .length;
    return _FetchWorkflowSummary(
      items: items,
      totalCount: steps.length,
      runningCount: runningCount,
      completedCount: completedCount,
      hasDetailContent: items.any((item) => item.subtitle.isNotEmpty),
    );
  }

  _FetchWorkflowItem _toItem(ToolWorkflowStep step) {
    final details = step.details;
    final url = (details['url'] ?? '').toString().trim();
    final host = _hostFromUrl(url);
    final prompt = (details['prompt'] ?? '').toString().trim();
    final failureReason = (details['failureReason'] ?? '').toString().trim();
    final resultPreview = (details['resultPreview'] ?? details['processedContent'])
        .toString()
        .trim();
    final subtitle = [
      if (prompt.isNotEmpty) prompt,
      if (failureReason.isNotEmpty) failureReason,
      if (prompt.isEmpty && failureReason.isEmpty && resultPreview.isNotEmpty)
        resultPreview,
    ].join(' · ');
    return _FetchWorkflowItem(
      step: step,
      title: host.isEmpty ? '网页内容' : host,
      subtitle: subtitle,
    );
  }

  String _hostFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.trim().isEmpty) {
      return url.trim();
    }
    return parsed.host.trim();
  }
}

class FetchWebpageToolUiRenderer extends ToolUiRenderer {
  const FetchWebpageToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return FetchWebpageToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return FetchWebpageToolWorkflowCard(
      steps: steps,
      expanded: isExpanded,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'fetch_webpage';

  @override
  bool supportsWorkflowStep(String toolName) =>
      toolName.trim() == 'fetch_webpage';
}

class _FetchWorkflowSummary {
  const _FetchWorkflowSummary({
    required this.items,
    required this.totalCount,
    required this.runningCount,
    required this.completedCount,
    required this.hasDetailContent,
  });

  final List<_FetchWorkflowItem> items;
  final int totalCount;
  final int runningCount;
  final int completedCount;
  final bool hasDetailContent;
}

class _FetchWorkflowItem {
  const _FetchWorkflowItem({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final ToolWorkflowStep step;
  final String title;
  final String subtitle;
}
