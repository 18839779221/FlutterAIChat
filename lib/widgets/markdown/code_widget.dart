import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/vs2015.dart';

class CodeConfig {
  static Map<String, TextStyle> theme = vs2015Theme;
  static TextStyle codeTextStyle = AppTypography.codeStyle(
    color: const Color(0xFFE6E6E6),
    fontSize: 13,
    height: 1.22,
  );

  bool autoLineBreak = true;
}

class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;
  final CodeConfig codeConfig = CodeConfig();

  CodeBlockWidget({super.key, required this.code, required this.language});

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(11, 0, 8, 0),
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF23272B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.language.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF8D959E),
                    fontSize: 8.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.32,
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                        width: 20,
                        height: 20,
                        child: IconButton(
                          iconSize: 11,
                          icon: Icon(
                            widget.codeConfig.autoLineBreak
                                ? Icons.wrap_text
                                : Icons.wrap_text_outlined,
                            color: widget.codeConfig.autoLineBreak
                                ? colors.workflowRunning.withValues(alpha: 0.72)
                                : const Color(0xFF78818A),
                          ),
                          tooltip: widget.codeConfig.autoLineBreak
                              ? '关闭自动换行'
                              : '开启自动换行',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          splashRadius: 5,
                          onPressed: () {
                            setState(() {
                              widget.codeConfig.autoLineBreak =
                                  !widget.codeConfig.autoLineBreak;
                            });
                          },
                        )),
                    const SizedBox(width: 1),
                    _CopyButton(code: widget.code),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: widget.codeConfig.autoLineBreak
                    ? highLightWidget(widget.code, widget.language)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: highLightWidget(widget.code, widget.language),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget highLightWidget(String code, String language) {
    return HighlightView(
      code,
      language: language,
      theme: CodeConfig.theme,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
      textStyle: CodeConfig.codeTextStyle,
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
        width: 20,
        height: 20,
        child: IconButton(
          iconSize: 11,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isCopied ? Icons.check : Icons.copy_outlined,
              key: ValueKey(_isCopied),
              color: _isCopied
                  ? const Color(0xFF7FBE95)
                  : const Color(0xFF78818A),
            ),
          ),
          tooltip: _isCopied ? '已复制' : '复制代码',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 16,
            minHeight: 16,
          ),
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
        color: const Color(0xFFDCE4EA),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        code,
        style: AppTypography.codeStyle(
          color: const Color(0xFF31414A),
          fontSize: 12.5,
          height: 1.18,
        ),
      ),
    );
  }
}
