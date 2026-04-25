import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_spacing.dart';
import 'research_tool_card_shell.dart';

class FetchWebpageToolResultCard extends StatefulWidget {
  const FetchWebpageToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  State<FetchWebpageToolResultCard> createState() =>
      _FetchWebpageToolResultCardState();
}

class _FetchWebpageToolResultCardState
    extends State<FetchWebpageToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.result.data;
    final url = (data['url'] ?? '').toString().trim();
    final host = _hostFromData(data, url);
    final prompt = (data['prompt'] ?? '').toString().trim();
    final preview = (data['resultPreview'] ??
            data['processedContent'] ??
            widget.result.summary)
        .toString()
        .trim();

    return ResearchToolCardShell(
      actionLabel: '读取网页',
      primaryText: '阅读网页 · ${host.isEmpty ? '网页内容' : host}',
      statusLabel: widget.result.statusLabel,
      statusColor: resultStatusColor(context, widget.result),
      expanded: _expanded,
      onTap: () => setState(() => _expanded = !_expanded),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prompt.isNotEmpty)
            Text(
              prompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (preview.isNotEmpty) ...[
            if (prompt.isNotEmpty)
              SizedBox(height: Theme.of(context).extension<AppSpacing>()!.xs),
            Text(
              preview,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
            ),
          ],
        ],
      ),
      expandedChild: _buildExpandedContent(context, data: data, url: url),
    );
  }

  Widget _buildExpandedContent(
    BuildContext context, {
    required Map<String, dynamic> data,
    required String url,
  }) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final prompt = (data['prompt'] ?? '').toString().trim();
    final preview = (data['resultPreview'] ?? '').toString().trim();
    final processedContent =
        (data['processedContent'] ?? preview).toString().trim();
    final finalUrl = (data['finalUrl'] ?? '').toString().trim();
    final redirectUrl = (data['redirectUrl'] ?? '').toString().trim();
    final rawExcerpt = (data['rawExcerpt'] ?? '').toString().trim();
    final failureReason = (data['failureReason'] ?? '').toString().trim();
    final title = (data['title'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Prompt',
          child: Text(
            prompt.isEmpty ? '未提供 prompt' : prompt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.45,
                ),
          ),
        ),
        SizedBox(height: spacing.sm),
        _SectionTitle(
          title: '处理结果',
          child: Text(
            processedContent.isEmpty ? widget.result.summary : processedContent,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.45,
                ),
          ),
        ),
        SizedBox(height: spacing.sm),
        _SectionTitle(
          title: '来源与细节',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) _DetailLine('标题', title),
              if (url.isNotEmpty) _DetailLine('原始地址', url),
              if (finalUrl.isNotEmpty && finalUrl != url)
                _DetailLine('最终地址', finalUrl),
              if (redirectUrl.isNotEmpty) _DetailLine('跳转地址', redirectUrl),
              if (failureReason.isNotEmpty) _DetailLine('失败原因', failureReason),
              if (rawExcerpt.isNotEmpty) _DetailLine('原始摘录', rawExcerpt),
            ],
          ),
        ),
      ],
    );
  }

  String _hostFromData(Map<String, dynamic> data, String url) {
    final host = (data['host'] ?? '').toString().trim();
    if (host.isNotEmpty) {
      return host;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.trim().isEmpty) {
      return url;
    }
    return parsed.host.trim();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        SizedBox(height: spacing.xs),
        child,
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Text(
        '$label：$value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              height: 1.4,
            ),
      ),
    );
  }
}
