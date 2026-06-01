import 'package:flutter/material.dart';

import '../../models/tool/tool_result.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../shared/file_highlight_language.dart';
import '../shared/highlighted_code_content.dart';
import '../technical_content_surface.dart';
import 'file_tool_result_surface.dart';

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
    final data = widget.result.data;
    final filePath = (data['filePath'] ?? '').toString();
    final existed = data['filePreviouslyExisted'] == true;
    final oldLength = data['oldLength'];
    final newLength = data['newLength'];
    final postWriteData = data['postWriteData'];
    final newContentPreview = (data['newContentPreview'] ?? '').toString();
    final hasPreview = newContentPreview.isNotEmpty;
    final language = fileHighlightLanguageForPath(filePath);

    return FileToolResultSurface(
      toolLabel: 'WRITE',
      filePath: filePath,
      primaryMeta: existed ? '覆盖文件' : '新建文件',
      secondaryMeta: oldLength is num && newLength is num
          ? '${oldLength.toInt()} -> ${newLength.toInt()} 字符'
          : null,
      summary: widget.result.summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPreview)
            TechnicalContentSurface(
              backgroundColor: colors.markdown.codePanelBackground,
              headerBackgroundColor:
                  colors.markdown.codeBlockBackground.withValues(
                alpha: 0.78,
              ),
              contentPadding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                child: HighlightedCodeContent(
                  code: newContentPreview,
                  language: language,
                ),
              ),
            ),
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
        style: AppTypography.uiStyle(
          color: colors.primaryText,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }
}
