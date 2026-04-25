import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
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
    final hasResults = summary.items.any((item) => item.results.isNotEmpty);

    return ResearchToolCardShell(
      actionLabel: '联网搜索',
      primaryText: _buildPrimaryText(summary),
      statusLabel: aggregateWorkflowStatusLabel(steps),
      statusColor: aggregateWorkflowStatusColor(context, steps),
      isRunning: steps.any((step) => step.status == ToolWorkflowStepStatus.running),
      expanded: expanded,
      footerHint: hasResults
          ? '查看来源'
          : canExpand
              ? '点击查看本批搜索状态'
              : null,
      body: _buildCollapsedBody(summary, expanded),
      onTap: hasResults
          ? () => _showResultsSheet(context, summary)
          : onTap,
      expandedChild:
          !hasResults && canExpand ? _buildExpandedContent(summary) : null,
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
                isRunning: summary.items[index].step.status ==
                    ToolWorkflowStepStatus.running,
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
    final results = _normalizeResults(details['results']);
    return _WebSearchWorkflowItem(
      step: step,
      title: title,
      subtitle: '',
      results: results,
    );
  }

  List<Map<String, dynamic>> _normalizeResults(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Future<void> _showResultsSheet(
    BuildContext context,
    _WebSearchWorkflowSummary summary,
  ) async {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final sections = summary.items
        .where((item) => item.results.isNotEmpty)
        .toList(growable: false);
    if (sections.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.chatBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius.lg)),
      ),
      builder: (sheetContext) {
        final totalResults = sections.fold<int>(
          0,
          (sum, item) => sum + item.results.length,
        );
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.78,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.sm,
                spacing.md,
                spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.secondaryText.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Text(
                    sections.length == 1 ? sections.first.title : '联网搜索结果',
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    '$totalResults 个来源',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  SizedBox(height: spacing.md),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var sectionIndex = 0;
                            sectionIndex < sections.length;
                            sectionIndex++) ...[
                          if (sections.length > 1) ...[
                            Text(
                              sections[sectionIndex].title,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: spacing.sm),
                          ],
                          for (var resultIndex = 0;
                              resultIndex < sections[sectionIndex].results.length;
                              resultIndex++) ...[
                            _WorkflowSearchResultItem(
                              item: sections[sectionIndex].results[resultIndex],
                            ),
                            if (resultIndex !=
                                sections[sectionIndex].results.length - 1)
                              SizedBox(height: spacing.sm),
                          ],
                          if (sectionIndex != sections.length - 1)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: spacing.md),
                              child: Divider(
                                height: 1,
                                color:
                                    colors.secondaryText.withValues(alpha: 0.14),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    required this.results,
  });

  final ToolWorkflowStep step;
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> results;
}

class _WorkflowSearchResultItem extends StatelessWidget {
  const _WorkflowSearchResultItem({
    required this.item,
  });

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final host = _resolvedHost(item);
    final title = (item['title'] ?? '').toString().trim();
    final snippet = (item['snippet'] ?? '').toString().trim();
    final url = (item['url'] ?? '').toString().trim();

    return InkWell(
      onTap: url.isEmpty ? null : () => _openUrl(url),
      borderRadius: BorderRadius.circular(radius.md),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.sm),
        decoration: BoxDecoration(
          color: colors.structuredSurface.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(radius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (title.isNotEmpty) ...[
              SizedBox(height: spacing.xxs),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (snippet.isNotEmpty) ...[
              SizedBox(height: spacing.xxs),
              Text(
                snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.42,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _resolvedHost(Map<String, dynamic> item) {
    final host = (item['source'] ?? '').toString().trim();
    if (host.isNotEmpty) {
      return host;
    }
    final url = (item['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(url);
    return uri?.host.trim().isNotEmpty == true ? uri!.host.trim() : '未知来源';
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}
