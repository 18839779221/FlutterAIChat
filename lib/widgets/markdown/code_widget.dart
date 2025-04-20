import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/vs2015.dart';

class CodeConfig {
  static Map<String, TextStyle> theme = vs2015Theme;
  static TextStyle codeTextStyle = const TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 14,
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 代码块头部
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 语言标识
                Text(
                  widget.language.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // 操作按钮
                Row(
                  children: [
                    // 自动换行按钮
                    SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          iconSize: 16,
                          icon: Icon(
                            widget.codeConfig.autoLineBreak
                                ? Icons.wrap_text
                                : Icons.wrap_text_outlined,
                            color: widget.codeConfig.autoLineBreak
                                ? Colors.blue
                                : Colors.grey[400],
                          ),
                          tooltip: widget.codeConfig.autoLineBreak
                              ? '关闭自动换行'
                              : '开启自动换行',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          splashRadius: 6,
                          onPressed: () {
                            setState(() {
                              widget.codeConfig.autoLineBreak =
                                  !widget.codeConfig.autoLineBreak;
                            });
                          },
                        )),
                    const SizedBox(width: 4),
                    // 复制按钮
                    _CopyButton(code: widget.code),
                  ],
                ),
              ],
            ),
          ),
          // 代码内容
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
        width: 36,
        height: 36,
        child: IconButton(
          iconSize: 16,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isCopied ? Icons.check : Icons.copy_outlined,
              key: ValueKey(_isCopied),
              color: _isCopied ? Colors.green : Colors.grey[400],
            ),
          ),
          tooltip: _isCopied ? '已复制' : '复制代码',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 20,
            minHeight: 20,
          ),
          splashRadius: 6,
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
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          backgroundColor: Colors.grey[200],
        ),
      ),
    );
  }
}
