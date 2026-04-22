import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

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

class _FetchWebpageToolResultCardState extends State<FetchWebpageToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final data = widget.result.data;
    final title = (data['title'] ?? '').toString();
    final url = (data['url'] ?? '').toString();
    final host = Uri.tryParse(url)?.host ?? '';
    final content = (data['content'] ?? '').toString();
    final extractMode = (data['extractMode'] ?? '').toString();

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
          Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (host.isNotEmpty) ...[
            SizedBox(height: spacing.xs),
            Text(
              host,
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
            child: Text(_expanded ? '收起正文' : '查看正文'),
          ),
          if (_expanded) ...[
            if (content.isNotEmpty)
              Text(
                content,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            if (extractMode.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing.xs),
                child: Text(
                  '提取模式：$extractMode',
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
