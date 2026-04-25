import 'package:ai_chat/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/a11y-dark.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ai_chat/theme/app_typography.dart';

import 'table_edge_fade_scroll_shell.dart';

class MarkdownWidgetImpl extends StatefulWidget {
  final String data;
  const MarkdownWidgetImpl({
    super.key,
    required this.data,
  });

  @override
  State<MarkdownWidgetImpl> createState() => _MarkdownWidgetImplState();
}

class _MarkdownWidgetImplState extends State<MarkdownWidgetImpl> {
  @override
  Widget build(BuildContext context) {
    return MarkdownBlock(
      data: widget.data,
      config: _getMarkdownConfig(context),
      selectable: false,
    );
  }

  MarkdownConfig _getMarkdownConfig(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.extension<AppColors>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = bodyColor.withValues(alpha: 0.84);
    final linkColor = theme.colorScheme.primary;
    final tableDividerColor =
        colors.divider.withValues(alpha: isDark ? 0.4 : 0.16);
    final tableHeaderFill =
        colors.toolWorkflowSurface.withValues(alpha: isDark ? 0.72 : 0.52);
    final tableBodyFill =
        colors.assistantSurface.withValues(alpha: isDark ? 0.2 : 0.08);
    final tableShellFill =
        colors.assistantSurface.withValues(alpha: isDark ? 0.3 : 0.14);

    return MarkdownConfig(
      configs: [
        PreConfig(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface
                .withValues(alpha: isDark ? 0.82 : 0.76),
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          theme: isDark ? a11yDarkTheme : a11yLightTheme,
          padding: const EdgeInsets.all(16),
          textStyle: AppTypography.codeStyle(
            color: bodyColor,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        CodeConfig(
          style: AppTypography.codeStyle(
            color: bodyColor.withValues(alpha: 0.92),
            fontSize: 12.5,
            height: 1.2,
          ),
        ),
        H1Config(
          style: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 18,
            height: 1.12,
            fontWeight: FontWeight.w500,
          ),
        ),
        H2Config(
          style: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 15,
            height: 1.14,
            fontWeight: FontWeight.w500,
          ),
        ),
        H3Config(
          style: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 14,
            height: 1.16,
            fontWeight: FontWeight.w500,
          ),
        ),
        PConfig(
          textStyle: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        BlockquoteConfig(
          textColor: secondaryColor,
          sideColor: colors.workflowRunning.withValues(alpha: 0.3),
          padding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        LinkConfig(
          style: AppTypography.documentStyle(
            color: linkColor,
            fontSize: 13,
            height: 1.4,
          ).copyWith(
            decoration: TextDecoration.underline,
          ),
          onTap: (url) {
            _launchUrl(url);
          },
        ),
        const ListConfig(
          marginLeft: 22,
          marginBottom: 4,
        ),
        TableConfig(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(
              color: tableDividerColor,
              width: 0.7,
            ),
          ),
          headerRowDecoration: BoxDecoration(
            color: tableHeaderFill,
          ),
          bodyRowDecoration: BoxDecoration(
            color: tableBodyFill,
          ),
          headerStyle: AppTypography.uiStyle(
            color: bodyColor,
            fontSize: 12.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.08,
          ),
          bodyStyle: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 12.8,
            height: 1.35,
          ),
          headPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          bodyPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          wrapper: (child) => Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: tableShellFill,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: TableEdgeFadeScrollShell(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      throw Exception('无法打开链接: $url');
    }
  }
}
