import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../technical_content_surface.dart';

enum _FileChangeLineKind {
  context,
  added,
  removed,
}

class _FileChangeLine {
  const _FileChangeLine({
    required this.kind,
    required this.lineNumber,
    required this.text,
  });

  final _FileChangeLineKind kind;
  final int? lineNumber;
  final String text;
}

class FileChangePreview extends StatelessWidget {
  const FileChangePreview({
    super.key,
    required this.oldContent,
    required this.newContent,
    required this.truncated,
    this.forceAdded = false,
  });

  /// Content before the file mutation. Empty for newly created files.
  final String oldContent;

  /// Content after the file mutation.
  final String newContent;

  /// Whether the preview content was shortened before reaching the UI.
  final bool truncated;

  /// Renders every line as an addition, used for new-file Write previews.
  final bool forceAdded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final lines = _buildLines();
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return TechnicalContentSurface(
      contentPadding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...lines.map((line) => _PreviewLineRow(line: line)),
            if (truncated)
              Padding(
                padding: EdgeInsets.all(spacing.sm),
                child: Text(
                  '预览已截断，仅展示前部内容',
                  style: AppTypography.uiStyle(
                    color: colors.secondaryText,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_FileChangeLine> _buildLines() {
    final oldLines = _splitLines(oldContent);
    final newLines = _splitLines(newContent);
    if (forceAdded || oldLines.isEmpty) {
      return [
        for (var index = 0; index < newLines.length; index += 1)
          _FileChangeLine(
            kind: _FileChangeLineKind.added,
            lineNumber: index + 1,
            text: newLines[index],
          ),
      ];
    }
    return _diffLines(oldLines, newLines);
  }

  List<String> _splitLines(String content) {
    if (content.isEmpty) {
      return const [];
    }
    return content.split('\n');
  }

  List<_FileChangeLine> _diffLines(
      List<String> oldLines, List<String> newLines) {
    final table = List.generate(
      oldLines.length + 1,
      (_) => List<int>.filled(newLines.length + 1, 0),
    );

    for (var oldIndex = oldLines.length - 1; oldIndex >= 0; oldIndex -= 1) {
      for (var newIndex = newLines.length - 1; newIndex >= 0; newIndex -= 1) {
        if (oldLines[oldIndex] == newLines[newIndex]) {
          table[oldIndex][newIndex] = table[oldIndex + 1][newIndex + 1] + 1;
        } else {
          final skipOld = table[oldIndex + 1][newIndex];
          final skipNew = table[oldIndex][newIndex + 1];
          table[oldIndex][newIndex] = skipOld > skipNew ? skipOld : skipNew;
        }
      }
    }

    final result = <_FileChangeLine>[];
    var oldIndex = 0;
    var newIndex = 0;
    while (oldIndex < oldLines.length && newIndex < newLines.length) {
      if (oldLines[oldIndex] == newLines[newIndex]) {
        result.add(
          _FileChangeLine(
            kind: _FileChangeLineKind.context,
            lineNumber: newIndex + 1,
            text: newLines[newIndex],
          ),
        );
        oldIndex += 1;
        newIndex += 1;
      } else if (table[oldIndex + 1][newIndex] >=
          table[oldIndex][newIndex + 1]) {
        result.add(
          _FileChangeLine(
            kind: _FileChangeLineKind.removed,
            lineNumber: oldIndex + 1,
            text: oldLines[oldIndex],
          ),
        );
        oldIndex += 1;
      } else {
        result.add(
          _FileChangeLine(
            kind: _FileChangeLineKind.added,
            lineNumber: newIndex + 1,
            text: newLines[newIndex],
          ),
        );
        newIndex += 1;
      }
    }

    while (oldIndex < oldLines.length) {
      result.add(
        _FileChangeLine(
          kind: _FileChangeLineKind.removed,
          lineNumber: oldIndex + 1,
          text: oldLines[oldIndex],
        ),
      );
      oldIndex += 1;
    }

    while (newIndex < newLines.length) {
      result.add(
        _FileChangeLine(
          kind: _FileChangeLineKind.added,
          lineNumber: newIndex + 1,
          text: newLines[newIndex],
        ),
      );
      newIndex += 1;
    }

    return result;
  }
}

class _PreviewLineRow extends StatelessWidget {
  const _PreviewLineRow({
    required this.line,
  });

  final _FileChangeLine line;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final background = _backgroundColor(colors);
    final textColor = _textColor(colors);
    final sign = _sign;

    return Container(
      color: background,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.xs,
        vertical: 3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              line.lineNumber?.toString() ?? '',
              textAlign: TextAlign.right,
              style: AppTypography.codeStyle(
                color: colors.secondaryText.withValues(alpha: 0.72),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(width: spacing.xs),
          Expanded(
            child: Text(
              '$sign ${line.text}',
              style: AppTypography.codeStyle(
                color: textColor,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _sign {
    switch (line.kind) {
      case _FileChangeLineKind.added:
        return '+';
      case _FileChangeLineKind.removed:
        return '-';
      case _FileChangeLineKind.context:
        return ' ';
    }
  }

  Color _backgroundColor(AppColors colors) {
    switch (line.kind) {
      case _FileChangeLineKind.added:
        return colors.workflowSuccess.withValues(alpha: 0.11);
      case _FileChangeLineKind.removed:
        return colors.workflowWarning.withValues(alpha: 0.11);
      case _FileChangeLineKind.context:
        return colors.assistantSurface.withValues(alpha: 0.08);
    }
  }

  Color _textColor(AppColors colors) {
    switch (line.kind) {
      case _FileChangeLineKind.added:
        return colors.workflowSuccess;
      case _FileChangeLineKind.removed:
        return colors.workflowWarning;
      case _FileChangeLineKind.context:
        return colors.primaryText.withValues(alpha: 0.84);
    }
  }
}
