import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/markdown/callout_block_syntax.dart';
import 'package:ai_chat/widgets/markdown/code_block_builder.dart';
import 'package:ai_chat/widgets/markdown/markdown_callout_builder.dart';
import 'package:ai_chat/widgets/markdown/markdown_math_builder.dart';
import 'package:ai_chat/widgets/markdown/math_block_syntax.dart';
import 'package:ai_chat/widgets/markdown/math_inline_syntax.dart';
import 'package:ai_chat/widgets/markdown/rich_table_inline_serializer.dart';
import 'package:ai_chat/widgets/markdown/table_edge_fade_scroll_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders <rich-table> AST sub-trees as a Flutter `Table` wrapped in a
/// [TableEdgeFadeScrollShell] inside a rounded panel.
///
/// Cell inline content is round-tripped through [RichTableInlineSerializer]
/// and rendered through a nested [MarkdownBody] so inline syntax (bold, em,
/// code, links, inline math) keeps working with the same theme as the
/// outer document.
class RichTableElementBuilder extends MarkdownElementBuilder {
  final bool selectable;

  RichTableElementBuilder({
    this.selectable = false,
  });

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'rich-table') return null;
    // Defer theme lookup until build so token recomputation tracks the
    // current Theme rather than the one captured at parse time.
    return Builder(builder: _buildShell(element));
  }

  WidgetBuilder _buildShell(md.Element table) {
    return (context) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final colors = theme.extension<AppThemeSpec>()!;
      final bodyColor = theme.colorScheme.onSurface;

      final tableDividerColor =
          colors.divider.withValues(alpha: isDark ? 0.4 : 0.16);
      final tableHeaderFill =
          colors.toolWorkflowSurface.withValues(alpha: isDark ? 0.72 : 0.52);
      final tableBodyFill =
          colors.assistantSurface.withValues(alpha: isDark ? 0.2 : 0.08);
      final tableShellFill =
          colors.assistantSurface.withValues(alpha: isDark ? 0.3 : 0.14);

      final headerStyle = AppTypography.uiStyle(
        color: bodyColor,
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.08,
      );
      final bodyStyle = AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 12.8,
        height: 1.35,
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final contentWidth = (availableWidth - 4).clamp(0.0, double.infinity);
          final cellMaxWidth =
              contentWidth > 0 ? contentWidth * 0.8 : double.infinity;
          final rows = _buildRows(
            table,
            headerStyle: headerStyle,
            bodyStyle: bodyStyle,
            tableHeaderFill: tableHeaderFill,
            tableBodyFill: tableBodyFill,
            cellMaxWidth: cellMaxWidth,
          );

          if (rows.isEmpty) return const SizedBox.shrink();

          final tableWidget = Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: tableDividerColor, width: 0.7),
            ),
            children: rows,
          );

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
                child: tableWidget,
              ),
            ),
          );
        },
      );
    };
  }

  List<TableRow> _buildRows(
    md.Element table, {
    required TextStyle headerStyle,
    required TextStyle bodyStyle,
    required Color tableHeaderFill,
    required Color tableBodyFill,
    required double cellMaxWidth,
  }) {
    final rows = <TableRow>[];
    _appendRows(
      rows,
      table,
      sectionTag: 'rich-thead',
      rowDecoration: BoxDecoration(color: tableHeaderFill),
      textStyle: headerStyle,
      defaultAlign: TextAlign.center,
      cellMaxWidth: cellMaxWidth,
    );
    _appendRows(
      rows,
      table,
      sectionTag: 'rich-tbody',
      rowDecoration: BoxDecoration(color: tableBodyFill),
      textStyle: bodyStyle,
      defaultAlign: TextAlign.left,
      cellMaxWidth: cellMaxWidth,
    );
    return rows;
  }

  void _appendRows(
    List<TableRow> out,
    md.Element table, {
    required String sectionTag,
    required BoxDecoration rowDecoration,
    required TextStyle textStyle,
    required TextAlign defaultAlign,
    required double cellMaxWidth,
  }) {
    final children = table.children;
    if (children == null) return;
    final section = children
        .whereType<md.Element>()
        .where((e) => e.tag == sectionTag)
        .cast<md.Element?>()
        .firstWhere((_) => true, orElse: () => null);
    if (section == null) return;
    final sectionChildren = section.children;
    if (sectionChildren == null) return;
    for (final node in sectionChildren) {
      if (node is! md.Element || node.tag != 'rich-tr') continue;
      final cells = node.children?.whereType<md.Element>().toList() ??
          const <md.Element>[];
      out.add(TableRow(
        decoration: rowDecoration,
        children: [
          for (final cell in cells)
            _buildCell(
              cell,
              textStyle: textStyle,
              defaultAlign: defaultAlign,
              maxWidth: cellMaxWidth,
            ),
        ],
      ));
    }
  }

  Widget _buildCell(
    md.Element cell, {
    required TextStyle textStyle,
    required TextAlign defaultAlign,
    double? maxWidth,
  }) {
    final align = _alignFor(cell, defaultAlign);
    final cellMarkdown = RichTableInlineSerializer.serialize(
      cell.children ?? const <md.Node>[],
    );
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? double.infinity,
          ),
          child: DefaultTextStyle(
            style: textStyle,
            textAlign: align,
            child: MarkdownBody(
              data: cellMarkdown,
              selectable: selectable,
              fitContent: true,
              extensionSet: md.ExtensionSet.gitHubFlavored,
              inlineSyntaxes: [MathInlineSyntax()],
              blockSyntaxes: const [
                MathBlockSyntax(),
                CalloutBlockSyntax(),
              ],
              builders: {
                'math-inline': MarkdownInlineMathBuilder(),
                'math-block': MarkdownBlockMathBuilder(),
                'callout': MarkdownCalloutBuilder(),
                'code': CodeElementBuilder(),
                'pre': CodeBlockBuilder(),
              },
              styleSheet: MarkdownStyleSheet(
                p: textStyle,
                blockSpacing: 0,
                textAlign: _wrapAlignFor(align),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextAlign _alignFor(md.Element cell, TextAlign fallback) {
    switch (cell.attributes['align']) {
      case 'left':
        return TextAlign.left;
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return fallback;
    }
  }

  WrapAlignment _wrapAlignFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return WrapAlignment.center;
      case TextAlign.right:
        return WrapAlignment.end;
      default:
        return WrapAlignment.start;
    }
  }
}
