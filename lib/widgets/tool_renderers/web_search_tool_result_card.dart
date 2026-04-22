import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class WebSearchToolResultCard extends StatefulWidget {
  const WebSearchToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  State<WebSearchToolResultCard> createState() => _WebSearchToolResultCardState();
}

class _WebSearchToolResultCardState extends State<WebSearchToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final data = widget.result.data;
    final query = (data['query'] ?? '').toString();
    final results = _normalizeResults(data['results']);
    final source = results.isEmpty ? '' : (results.first['source'] ?? '').toString();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.toolOutcomeSurface,
        borderRadius: BorderRadius.circular(radius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (query.isNotEmpty)
            Text(
              query,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (results.isNotEmpty) ...[
            SizedBox(height: spacing.xs),
            Text(
              '${results.length} 条结果',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (source.isNotEmpty) ...[
            SizedBox(height: spacing.xxs),
            Text(
              source,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 12,
              ),
            ),
          ],
          SizedBox(height: spacing.xs),
          Text(
            widget.result.summary,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 12.5,
              height: 1.42,
            ),
          ),
          SizedBox(height: spacing.sm),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起来源' : '查看来源'),
          ),
          if (_expanded)
            ...results.map(
              (item) => Padding(
                padding: EdgeInsets.only(top: spacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['title'] ?? '').toString(),
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((item['snippet'] ?? '').toString().isNotEmpty)
                      Text(
                        (item['snippet'] ?? '').toString(),
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _normalizeResults(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
}
