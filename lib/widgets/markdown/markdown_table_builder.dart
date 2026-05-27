import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'table_edge_fade_scroll_shell.dart';

class MarkdownTableBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  void visitElementBefore(md.Element element) {
    print('MarkdownTableBuilder.visitElementBefore: tag=${element.tag}');
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    print('MarkdownTableBuilder.visitText called');
    // 返回空 widget 阻止默认文本处理
    return const SizedBox.shrink();
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    print('MarkdownTableBuilder.visitElementAfter called: tag=${element.tag}');
    if (element.tag != 'table') return null;

    print('Building EnhancedMarkdownTable');
    final tableData = _extractTableData(element);

    return EnhancedMarkdownTable(
      headerCells: tableData.headerCells,
      bodyCells: tableData.bodyCells,
      columnAlignments: tableData.columnAlignments,
    );
  }

  _TableData _extractTableData(md.Element element) {
    final headerCells = <String>[];
    final bodyCells = <List<String>>[];
    final columnAlignments = <int, TextAlign>{};

    for (final child in element.children ?? []) {
      if (child.tag == 'thead') {
        for (final row in child.children ?? []) {
          if (row.tag == 'tr') {
            for (final cell in row.children ?? []) {
              if (cell.tag == 'th') {
                headerCells.add(cell.textContent);
                final align = _extractAlignment(cell);
                if (align != null) {
                  columnAlignments[headerCells.length - 1] = align;
                }
              }
            }
          }
        }
      } else if (child.tag == 'tbody') {
        for (final row in child.children ?? []) {
          if (row.tag == 'tr') {
            final rowCells = <String>[];
            for (final cell in row.children ?? []) {
              if (cell.tag == 'td') {
                rowCells.add(cell.textContent);
              }
            }
            if (rowCells.isNotEmpty) {
              bodyCells.add(rowCells);
            }
          }
        }
      }
    }

    return _TableData(
      headerCells: headerCells,
      bodyCells: bodyCells,
      columnAlignments: columnAlignments,
    );
  }

  TextAlign? _extractAlignment(md.Element cell) {
    final style = cell.attributes['style'];
    if (style == null) return null;

    if (style.contains('text-align: center')) return TextAlign.center;
    if (style.contains('text-align: right')) return TextAlign.right;
    if (style.contains('text-align: left')) return TextAlign.left;

    return null;
  }
}

class _TableData {
  final List<String> headerCells;
  final List<List<String>> bodyCells;
  final Map<int, TextAlign> columnAlignments;

  _TableData({
    required this.headerCells,
    required this.bodyCells,
    required this.columnAlignments,
  });
}

class EnhancedMarkdownTable extends StatelessWidget {
  final List<String> headerCells;
  final List<List<String>> bodyCells;
  final Map<int, TextAlign> columnAlignments;

  const EnhancedMarkdownTable({
    super.key,
    required this.headerCells,
    required this.bodyCells,
    required this.columnAlignments,
  });

  @override
  Widget build(BuildContext context) {
    if (headerCells.isEmpty && bodyCells.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeSpec>()!;
    final bodyColor = theme.colorScheme.onSurface;

    final tableEdgeColor = colors.artifactBorderStrong;
    final tableDividerColor = colors.artifactBorderStrong.withValues(alpha: 0.7);
    final tableHeaderFill = colors.toolWorkflowSurface;
    final tableBodyFill = colors.assistantSurface.withValues(alpha: 0.08);
    final tableShellFill = colors.assistantSurface.withValues(alpha: 0.14);

    final headerStyle = TextStyle(
      color: bodyColor,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.08,
      height: 1.2,
    );

    final bodyStyle = TextStyle(
      color: bodyColor,
      fontSize: 12.8,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );

    final rows = <TableRow>[];

    if (headerCells.isNotEmpty) {
      rows.add(
        TableRow(
          decoration: BoxDecoration(color: tableHeaderFill),
          children: headerCells.asMap().entries.map((entry) {
            final index = entry.key;
            final cell = entry.value;
            return TableCell(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Text(
                  cell,
                  style: headerStyle,
                  textAlign: columnAlignments[index] ?? TextAlign.left,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    for (final rowCells in bodyCells) {
      rows.add(
        TableRow(
          decoration: BoxDecoration(color: tableBodyFill),
          children: rowCells.asMap().entries.map((entry) {
            final index = entry.key;
            final cell = entry.value;
            return TableCell(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Text(
                  cell,
                  style: bodyStyle,
                  textAlign: columnAlignments[index] ?? TextAlign.left,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: tableShellFill,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: TableEdgeFadeScrollShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(
              top: BorderSide(color: tableEdgeColor, width: 0.9),
              bottom: BorderSide(color: tableEdgeColor, width: 0.9),
              left: BorderSide(color: tableEdgeColor, width: 0.9),
              right: BorderSide(color: tableEdgeColor, width: 0.9),
              horizontalInside: BorderSide(color: tableDividerColor, width: 0.8),
              verticalInside: BorderSide(color: tableDividerColor, width: 0.8),
            ),
            children: rows,
          ),
        ),
      ),
    );
  }
}
