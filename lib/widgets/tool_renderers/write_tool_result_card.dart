import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'file_change_preview.dart';

class WriteToolResultCard extends StatefulWidget {
  const WriteToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  State<WriteToolResultCard> createState() => _WriteToolResultCardState();
}

class _WriteToolResultCardState extends State<WriteToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final data = widget.result.data;
    final filePath = (data['filePath'] ?? '').toString();
    final existed = data['filePreviouslyExisted'] == true;
    final oldLength = data['oldLength'];
    final newLength = data['newLength'];
    final postWriteData = data['postWriteData'];
    final oldContentPreview = (data['oldContentPreview'] ?? '').toString();
    final newContentPreview = (data['newContentPreview'] ?? '').toString();
    final hasPreview = newContentPreview.isNotEmpty;

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
            filePath,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            existed ? '覆盖文件' : '新建文件',
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (oldLength is num && newLength is num) ...[
            SizedBox(height: spacing.xxs),
            Text(
              '${oldLength.toInt()} -> ${newLength.toInt()} 字符',
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
          if (hasPreview) ...[
            SizedBox(height: spacing.sm),
            FileChangePreview(
              oldContent: oldContentPreview,
              newContent: newContentPreview,
              truncated: data['contentPreviewTruncated'] == true,
              forceAdded: !existed,
            ),
          ],
          SizedBox(height: spacing.sm),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起详情' : '查看详情'),
          ),
          if (_expanded) ...[
            if (data['fileVersion'] != null)
              _DetailLine(
                label: 'fileVersion',
                value: '${data['fileVersion']}',
              ),
            if (postWriteData != null) ...[
              const _DetailLine(
                label: '',
                value: 'postWriteData',
              ),
              ..._expandMap(postWriteData).entries.map(
                    (entry) => _DetailLine(
                      label: '',
                      value: '${entry.key}: ${entry.value}',
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _expandMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.only(top: spacing.xxs),
      child: Text(
        label.isEmpty ? value : '$label: $value',
        style: TextStyle(
          color: colors.primaryText,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }
}
