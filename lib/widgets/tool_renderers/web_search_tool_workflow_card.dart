import 'package:flutter/material.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_spacing.dart';
import 'research_tool_card_shell.dart';
import 'web_search_tool_result_card.dart';

class WebSearchToolWorkflowCard extends StatelessWidget {
  const WebSearchToolWorkflowCard({
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
    final canExpand = summary.totalCount > 1;

    return ResearchToolCardShell(
      actionLabel: '联网搜索',
      primaryText: _buildPrimaryText(summary),
      statusLabel: aggregateWorkflowStatusLabel(steps),
      statusColor: aggregateWorkflowStatusColor(context, steps),
      expanded: expanded,
      footerHint: canExpand ? '点击查看本批搜索状态' : null,
      body: _buildCollapsedBody(summary, expanded),
      onTap: onTap,
      expandedChild: canExpand ? _buildExpandedContent(summary) : null,
    );
  }

  Widget? _buildCollapsedBody(_WebSearchWorkflowSummary summary, bool expanded) {
    final previewText = _buildPreviewText(summary);
    if (previewText == null) {
      return null;
    }
    return Builder(
      builder: (context) => Text(
        previewText,
        maxLines: expanded ? null : 2,
        overflow: expanded ? null : TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              height: 1.4,
            ),
      ),
    );
  }

  Widget _buildExpandedContent(_WebSearchWorkflowSummary summary) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final spacing = theme.extension<AppSpacing>()!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本批共 ${summary.totalCount} 个搜索请求',
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

  String _buildPrimaryText(_WebSearchWorkflowSummary summary) {
    if (summary.totalCount <= 1) {
      return summary.items.isEmpty ? '搜索中' : summary.items.first.title;
    }
    if (summary.runningCount > 1) {
      return '并行搜索 ${summary.runningCount} 个查询';
    }
    if (summary.completedCount == summary.totalCount) {
      return '已完成 ${summary.totalCount} 个搜索';
    }
    return '联网搜索 · ${summary.totalCount} 个查询';
  }

  String? _buildPreviewText(_WebSearchWorkflowSummary summary) {
    if (summary.totalCount <= 1) {
      final subtitle = summary.items.isEmpty ? '' : summary.items.first.subtitle;
      final trimmed = subtitle.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final previewItems = summary.items.take(2).map((item) => item.title).toList();
    if (previewItems.isEmpty) {
      return null;
    }
    final remaining = summary.totalCount - previewItems.length;
    if (remaining > 0) {
      previewItems.add('以及另外 $remaining 个查询');
    }
    return previewItems.join('\n');
  }

  _WebSearchWorkflowSummary _summarizeSteps(List<ToolWorkflowStep> steps) {
    final items = steps.map(_toItem).toList(growable: false);
    return _WebSearchWorkflowSummary(
      items: items,
      totalCount: steps.length,
      runningCount: steps
          .where((step) => step.status == ToolWorkflowStepStatus.running)
          .length,
      completedCount: steps
          .where((step) => step.status == ToolWorkflowStepStatus.completed)
          .length,
    );
  }

  _WebSearchWorkflowItem _toItem(ToolWorkflowStep step) {
    final details = step.details;
    final query = (details['query'] ?? '').toString().trim();
    final title = query.isEmpty ? '搜索请求' : query;
    return _WebSearchWorkflowItem(
      step: step,
      title: title,
      subtitle: '',
    );
  }
}

class WebSearchToolUiRenderer extends ToolUiRenderer {
  const WebSearchToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return WebSearchToolResultCard(result: result);
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return WebSearchToolWorkflowCard(
      steps: steps,
      expanded: isExpanded,
      onTap: onTap,
    );
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == 'web_search';

  @override
  bool supportsWorkflowStep(String toolName) => toolName.trim() == 'web_search';
}

class _WebSearchWorkflowSummary {
  const _WebSearchWorkflowSummary({
    required this.items,
    required this.totalCount,
    required this.runningCount,
    required this.completedCount,
  });

  final List<_WebSearchWorkflowItem> items;
  final int totalCount;
  final int runningCount;
  final int completedCount;
}

class _WebSearchWorkflowItem {
  const _WebSearchWorkflowItem({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final ToolWorkflowStep step;
  final String title;
  final String subtitle;
}
