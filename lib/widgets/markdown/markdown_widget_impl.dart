import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ai_chat/theme/app_typography.dart';

import 'code_widget.dart';
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
    final config = _getMarkdownConfig(context);
    return DefaultTextStyle.merge(
      style: config.p.textStyle,
      child: MarkdownBlock(
        data: widget.data,
        config: config,
        selectable: false,
      ),
    );
  }

  MarkdownConfig _getMarkdownConfig(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.extension<AppThemeSpec>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final bodyStyle = AppTypography.documentStyle(
      color: bodyColor,
      fontSize: 13,
      height: 1.46,
    );
    final secondaryColor = bodyColor.withValues(alpha: 0.84);
    final linkColor = theme.colorScheme.primary;
    final tableEdgeColor =
        colors.artifactBorderStrong.withValues(alpha: isDark ? 0.72 : 0.92);
    final tableDividerColor =
        colors.artifactBorderStrong.withValues(alpha: isDark ? 0.54 : 0.68);
    final tableHeaderFill =
        colors.toolWorkflowSurface.withValues(alpha: isDark ? 0.72 : 0.52);
    final tableBodyFill =
        colors.assistantSurface.withValues(alpha: isDark ? 0.2 : 0.08);
    final tableShellFill =
        colors.assistantSurface.withValues(alpha: isDark ? 0.3 : 0.14);

    return MarkdownConfig(
      configs: [
        PreConfig(
          margin: const EdgeInsets.symmetric(vertical: 4),
          builder: (code, language) => CodeBlockWidget(
            code: code,
            language: language,
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
        _MarkdownH2Config(
          style: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 15,
            height: 1.14,
            fontWeight: FontWeight.w500,
          ),
        ),
        _MarkdownH3Config(
          style: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 14,
            height: 1.16,
            fontWeight: FontWeight.w500,
          ),
        ),
        PConfig(textStyle: bodyStyle),
        HrConfig(
          height: 1,
          color: colors.divider.withValues(alpha: isDark ? 0.18 : 0.1),
        ),
        BlockquoteConfig(
          textColor: secondaryColor,
          sideColor: colors.workflowRunning.withValues(alpha: 0.18),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          margin: const EdgeInsets.symmetric(vertical: 6),
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
          marginLeft: 24,
          marginBottom: 6,
        ),
        TableConfig(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            top: BorderSide(
              color: tableEdgeColor,
              width: 0.9,
            ),
            bottom: BorderSide(
              color: tableEdgeColor,
              width: 0.9,
            ),
            left: BorderSide(
              color: tableEdgeColor,
              width: 0.9,
            ),
            right: BorderSide(
              color: tableEdgeColor,
              width: 0.9,
            ),
            horizontalInside: BorderSide(
              color: tableDividerColor,
              width: 0.8,
            ),
            verticalInside: BorderSide(
              color: tableDividerColor,
              width: 0.8,
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
            margin: const EdgeInsets.symmetric(vertical: 8),
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

class _MarkdownH2Config extends H2Config {
  const _MarkdownH2Config({required super.style});

  @override
  HeadingDivider? get divider => null;

  @override
  EdgeInsets get padding => const EdgeInsets.only(top: 14, bottom: 7);
}

class _MarkdownH3Config extends H3Config {
  const _MarkdownH3Config({required super.style});

  @override
  HeadingDivider? get divider => null;

  @override
  EdgeInsets get padding => const EdgeInsets.only(top: 11, bottom: 6);
}
