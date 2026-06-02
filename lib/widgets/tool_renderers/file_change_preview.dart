import 'package:flutter/material.dart';

import '../../theme/app_theme_spec.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../shared/file_highlight_language.dart';
import '../shared/highlighted_code_content.dart';
import '../technical_content_surface.dart';

const int _previewContextLines = 2;

enum _FileChangeLineKind {
  context,
  added,
  removed,
}

class _FileChangeLine {
  const _FileChangeLine({
    required this.kind,
    required this.displayLineNumber,
    required this.text,
  });

  final _FileChangeLineKind kind;
  final int? displayLineNumber;
  final String text;
}

class _DisplayItem {
  const _DisplayItem.line(this.line) : isDivider = false;
  const _DisplayItem.divider()
      : line = null,
        isDivider = true;

  final _FileChangeLine? line;
  final bool isDivider;
}

class FileChangePreview extends StatelessWidget {
  const FileChangePreview({
    super.key,
    required this.filePath,
    required this.oldContent,
    required this.newContent,
    required this.truncated,
    this.forceAdded = false,
  });

  final String filePath;
  final String oldContent;
  final String newContent;
  final bool truncated;
  final bool forceAdded;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final language = fileHighlightLanguageForPath(filePath);
    final items = _buildDisplayItems();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return TechnicalContentSurface(
      contentPadding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              item.isDivider
                  ? const _PreviewDivider()
                  : _PreviewLineRow(
                      line: item.line!,
                      language: language,
                    ),
            if (truncated)
              Padding(
                padding: EdgeInsets.all(spacing.sm),
                child: Text(
                  '预览已截断，仅展示前部内容',
                  style: AppTypography.uiStyle(
                    color: AppThemeSpec.of(context).secondaryText,
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

  List<_DisplayItem> _buildDisplayItems() {
    final lines = _buildLines();
    if (lines.isEmpty) {
      return const [];
    }
    final hasContextLine = lines.any(
      (line) => line.kind == _FileChangeLineKind.context,
    );
    if (!hasContextLine) {
      return [for (final line in lines) _DisplayItem.line(line)];
    }

    final changeRanges = <({int start, int end})>[];
    var changeStart = -1;
    for (var index = 0; index < lines.length; index += 1) {
      final isChanged = lines[index].kind != _FileChangeLineKind.context;
      if (isChanged && changeStart == -1) {
        changeStart = index;
      }
      if (!isChanged && changeStart != -1) {
        changeRanges.add((start: changeStart, end: index - 1));
        changeStart = -1;
      }
    }
    if (changeStart != -1) {
      changeRanges.add((start: changeStart, end: lines.length - 1));
    }
    if (changeRanges.isEmpty) {
      return [for (final line in lines) _DisplayItem.line(line)];
    }

    final ranges = <({int start, int end})>[];
    for (final changeRange in changeRanges) {
      final start = changeRange.start - _previewContextLines < 0
          ? 0
          : changeRange.start - _previewContextLines;
      final end = changeRange.end + _previewContextLines >= lines.length
          ? lines.length - 1
          : changeRange.end + _previewContextLines;
      if (ranges.isEmpty) {
        ranges.add((start: start, end: end));
        continue;
      }
      final previous = ranges.last;
      if (start <= previous.end + 1) {
        ranges[ranges.length - 1] = (
          start: previous.start,
          end: end > previous.end ? end : previous.end,
        );
      } else {
        ranges.add((start: start, end: end));
      }
    }

    final items = <_DisplayItem>[];
    for (var index = 0; index < ranges.length; index += 1) {
      final range = ranges[index];
      for (var lineIndex = range.start; lineIndex <= range.end; lineIndex += 1) {
        items.add(_DisplayItem.line(lines[lineIndex]));
      }
      if (index < ranges.length - 1) {
        items.add(const _DisplayItem.divider());
      }
    }
    return items;
  }

  List<_FileChangeLine> _buildLines() {
    final oldLines = _splitLines(oldContent);
    final newLines = _splitLines(newContent);
    if (forceAdded || oldLines.isEmpty) {
      return [
        for (var index = 0; index < newLines.length; index += 1)
          _FileChangeLine(
            kind: _FileChangeLineKind.added,
            displayLineNumber: index + 1,
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
    List<String> oldLines,
    List<String> newLines,
  ) {
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
            displayLineNumber: newIndex + 1,
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
            displayLineNumber: oldIndex + 1,
            text: oldLines[oldIndex],
          ),
        );
        oldIndex += 1;
      } else {
        result.add(
          _FileChangeLine(
            kind: _FileChangeLineKind.added,
            displayLineNumber: newIndex + 1,
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
          displayLineNumber: oldIndex + 1,
          text: oldLines[oldIndex],
        ),
      );
      oldIndex += 1;
    }

    while (newIndex < newLines.length) {
      result.add(
        _FileChangeLine(
          kind: _FileChangeLineKind.added,
          displayLineNumber: newIndex + 1,
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
    required this.language,
  });

  final _FileChangeLine line;
  final String language;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final background = _backgroundColor(colors);
    final textColor = _textColor(colors);

    return Container(
      color: background,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.xs,
        vertical: 3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LineNumberCell(number: line.displayLineNumber, color: textColor),
          SizedBox(width: spacing.xxs),
          SizedBox(
            width: 12,
            child: Text(
              _sign,
              textAlign: TextAlign.center,
              style: AppTypography.codeStyle(
                color: textColor,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: spacing.xxs),
          Expanded(
            child: HighlightedCodeContent(
              code: line.text,
              language: language,
              fontSize: 12,
              lineHeight: 1.5,
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

  Color _backgroundColor(AppThemeSpec colors) {
    switch (line.kind) {
      case _FileChangeLineKind.added:
        return colors.workflowSuccess.withValues(alpha: 0.11);
      case _FileChangeLineKind.removed:
        return colors.workflowWarning.withValues(alpha: 0.11);
      case _FileChangeLineKind.context:
        return colors.assistantSurface.withValues(alpha: 0.08);
    }
  }

  Color _textColor(AppThemeSpec colors) {
    switch (line.kind) {
      case _FileChangeLineKind.added:
        return colors.workflowSuccess;
      case _FileChangeLineKind.removed:
        return colors.workflowWarning;
      case _FileChangeLineKind.context:
        return colors.primaryText.withValues(alpha: 0.7);
    }
  }
}

class _LineNumberCell extends StatelessWidget {
  const _LineNumberCell({
    required this.number,
    required this.color,
  });

  final int? number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Text(
        number?.toString() ?? '',
        textAlign: TextAlign.right,
        style: AppTypography.codeStyle(
          color: color.withValues(alpha: 0.72),
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }
}

class _PreviewDivider extends StatelessWidget {
  const _PreviewDivider();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xxs + 2,
      ),
      color: colors.assistantSurface.withValues(alpha: 0.05),
      child: Text(
        '...',
        style: AppTypography.codeStyle(
          color: colors.secondaryText,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }
}
