import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/a11y-dark.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';

import '../technical_content_surface.dart';
import 'flutter_markdown_reader_tokens.dart';

class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;

  const CodeBlockWidget({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _autoLineBreak = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final reader = FlutterMarkdownReaderTokens.build(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: reader.codeBlockBackgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: _autoLineBreak
              ? _highlightWidget(context)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _highlightWidget(context),
                ),
        ),
      ),
    );

    return TechnicalContentSurface(
      backgroundColor: reader.codePanelBackgroundColor,
      headerBackgroundColor: reader.codeBlockBackgroundColor.withValues(
        alpha: 0.78,
      ),
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TechnicalContentLabel(text: widget.language.toUpperCase()),
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: IconButton(
                  iconSize: 10.5,
                  icon: Icon(
                    _autoLineBreak ? Icons.wrap_text : Icons.wrap_text_outlined,
                    color: _autoLineBreak
                        ? colors.workflowRunning.withValues(alpha: 0.58)
                        : colors.secondaryText.withValues(alpha: 0.68),
                  ),
                  tooltip: _autoLineBreak ? '关闭自动换行' : '开启自动换行',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 5,
                  onPressed: () {
                    setState(() {
                      _autoLineBreak = !_autoLineBreak;
                    });
                  },
                ),
              ),
              const SizedBox(width: 1),
              _CopyButton(code: widget.code),
            ],
          ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      child: content,
    );
  }

  Widget _highlightWidget(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseTheme = isDark ? a11yDarkTheme : a11yLightTheme;
    final highlightTheme = Map<String, TextStyle>.from(baseTheme);
    final rootStyle = highlightTheme['root'] ?? const TextStyle();
    highlightTheme['root'] = rootStyle.copyWith(
      backgroundColor: Colors.transparent,
    );

    return HighlightView(
      widget.code,
      language: widget.language,
      theme: highlightTheme,
      padding: EdgeInsets.zero,
      textStyle: AppTypography.codeStyle(
        color: isDark ? const Color(0xFFE6E6E6) : const Color(0xFF31414A),
        fontSize: 12.5,
        height: 1.45,
      ),
    );
  }
}

// 复制按钮组件
class _CopyButton extends StatefulWidget {
  final String code;

  const _CopyButton({required this.code});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _isCopied = false;

  void _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _isCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isCopied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: 18,
        height: 18,
        child: IconButton(
          iconSize: 10.5,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isCopied ? Icons.check : Icons.copy_outlined,
              key: ValueKey(_isCopied),
              color: _isCopied
                  ? const Color(0xFF7FBE95)
                  : Theme.of(context)
                      .extension<AppThemeSpec>()!
                      .secondaryText
                      .withValues(alpha: 0.68),
            ),
          ),
          tooltip: _isCopied ? '已复制' : '复制代码',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 16,
            minHeight: 16,
          ),
          visualDensity: VisualDensity.compact,
          splashRadius: 5,
          onPressed: _copyCode,
        ));
  }
}

class CodeSegmentWidget extends StatelessWidget {
  final String code;

  const CodeSegmentWidget({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .extension<AppThemeSpec>()!
            .toolWorkflowSurface
            .withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        code,
        style: AppTypography.codeStyle(
          color: Theme.of(context)
              .extension<AppThemeSpec>()!
              .primaryText
              .withValues(alpha: 0.9),
          fontSize: 12.5,
          height: 1.18,
        ),
      ),
    );
  }
}
