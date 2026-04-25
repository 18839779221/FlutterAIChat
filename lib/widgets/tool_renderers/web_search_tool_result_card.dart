import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'research_tool_card_shell.dart';

class WebSearchToolResultCard extends StatelessWidget {
  const WebSearchToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    final query = (data['query'] ?? '').toString();
    final results = _normalizeResults(data['results']);

    return ResearchToolCardShell(
      actionLabel: '联网搜索',
      primaryText: _buildPrimaryText(
        query: query,
        resultsCount: results.length,
      ),
      statusLabel: result.statusLabel,
      statusColor: resultStatusColor(context, result),
      footerHint: results.isEmpty ? null : '查看来源',
      onTap: results.isEmpty
          ? null
          : () => _showResultsSheet(context, query, results),
    );
  }

  String _buildPrimaryText({
    required String query,
    required int resultsCount,
  }) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return resultsCount <= 0 ? '搜索结果' : '$resultsCount 个来源';
    }
    if (resultsCount <= 0) {
      return trimmedQuery;
    }
    return '$trimmedQuery · $resultsCount 个来源';
  }

  List<Map<String, dynamic>> _normalizeResults(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Future<void> _showResultsSheet(
    BuildContext context,
    String query,
    List<Map<String, dynamic>> results,
  ) async {
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
                    query.trim().isEmpty ? '联网搜索结果' : query.trim(),
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    '${results.length} 个来源',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  SizedBox(height: spacing.md),
                  Expanded(
                    child: ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (context, index) =>
                          SizedBox(height: spacing.sm),
                      itemBuilder: (itemContext, index) => _SearchResultItem(
                        item: results[index],
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
}

class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({
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
            Row(
              children: [
                _FaviconBadge(host: host),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (url.isNotEmpty)
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: colors.secondaryText,
                  ),
              ],
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

class _FaviconBadge extends StatefulWidget {
  const _FaviconBadge({
    required this.host,
  });

  final String host;

  @override
  State<_FaviconBadge> createState() => _FaviconBadgeState();
}

class _FaviconBadgeState extends State<_FaviconBadge> {
  static final Map<String, ImageProvider> _providerCache =
      <String, ImageProvider>{};
  static final Set<String> _failedHosts = <String>{};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final host = widget.host.trim();
    final fallback = Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        host.isEmpty ? '?' : host.characters.first.toUpperCase(),
        style: TextStyle(
          color: colors.secondaryText,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (host.isEmpty || host == '未知来源' || _failedHosts.contains(host)) {
      return fallback;
    }

    final provider = _providerCache.putIfAbsent(
      host,
      () => NetworkImage('https://$host/favicon.ico'),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image(
        image: provider,
        width: 18,
        height: 18,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          _failedHosts.add(host);
          return fallback;
        },
      ),
    );
  }
}
