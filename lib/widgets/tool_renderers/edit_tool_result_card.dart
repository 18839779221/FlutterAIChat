import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'file_change_preview.dart';
import 'file_tool_result_surface.dart';

class EditToolResultCard extends StatefulWidget {
  const EditToolResultCard({
    super.key,
    required this.result,
  });

  final ToolResult result;

  @override
  State<EditToolResultCard> createState() => _EditToolResultCardState();
}

class _EditToolResultCardState extends State<EditToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final data = widget.result.data;
    final filePath = (data['filePath'] ?? '').toString();
    final replacementCount = data['replacementCount'];
    final oldLength = data['oldLength'];
    final newLength = data['newLength'];
    final oldContentPreview = (data['oldContentPreview'] ?? '').toString();
    final newContentPreview = (data['newContentPreview'] ?? '').toString();
    final hasPreview =
        oldContentPreview.isNotEmpty || newContentPreview.isNotEmpty;

    return FileToolResultSurface(
      toolLabel: 'EDIT',
      filePath: filePath,
      primaryMeta: replacementCount is num
          ? '替换 ${replacementCount.toInt()} 处'
          : null,
      secondaryMeta: oldLength is num && newLength is num
          ? '${oldLength.toInt()} -> ${newLength.toInt()} 字符'
          : null,
      summary: widget.result.summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPreview)
            FileChangePreview(
              filePath: filePath,
              oldContent: oldContentPreview,
              newContent: newContentPreview,
              truncated: data['contentPreviewTruncated'] == true,
            ),
          SizedBox(height: spacing.sm),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起详情' : '查看详情'),
          ),
          if (_expanded) ...[
            if ((data['oldString'] ?? '').toString().isNotEmpty)
              _DetailLine(label: '', value: '${data['oldString']}'),
            if ((data['newString'] ?? '').toString().isNotEmpty)
              _DetailLine(label: '', value: '${data['newString']}'),
          ],
        ],
      ),
    );
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
        style: AppTypography.uiStyle(
          color: colors.primaryText,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }
}
