import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../markdown/flutter_markdown_impl.dart';
import 'research_tool_card_shell.dart';

class FetchWebpageToolResultCard extends StatelessWidget {
  const FetchWebpageToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final url = (data['url'] ?? '').toString().trim();
    final host = _hostFromData(data, url);
    final prompt = (data['prompt'] ?? '').toString().trim();
    final preview = (data['resultPreview'] ??
            data['processedContent'] ??
            result.summary)
        .toString()
        .trim();

    return ResearchToolCardShell(
      actionLabel: '读取网页',
      primaryText: '阅读网页 · ${host.isEmpty ? '网页内容' : host}',
      statusLabel: result.statusLabel,
      statusColor: resultStatusColor(context, result),
      footerHint: '查看详情',
      onTap: () => _showDetailsSheet(context, data: data, url: url),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showDetailsSheet(
    BuildContext context, {
    required Map<String, dynamic> data,
    required String url,
  }) async {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.chatBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius.lg)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.82,
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
                    _sheetTitle(data, url),
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  SizedBox(height: spacing.md),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildExpandedContent(
                        sheetContext,
                        data: data,
                        url: url,
                      ),
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
          child: FlutterMarkdownImpl(
            data: processedContent.isEmpty ? result.summary : processedContent,
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

  String _sheetTitle(Map<String, dynamic> data, String url) {
    final title = (data['title'] ?? '').toString().trim();
    if (title.isNotEmpty) {
      return title;
    }
    final host = _hostFromData(data, url);
    return host.isEmpty ? '网页详情' : host;
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
