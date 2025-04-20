import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/a11y-dark.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class MarkdownWidgetImpl extends StatefulWidget {
  final String data;
  const MarkdownWidgetImpl({
    Key? key,
    required this.data,
  }) : super(key: key);

  @override
  State<MarkdownWidgetImpl> createState() => _MarkdownWidgetImplState();
}

class _MarkdownWidgetImplState extends State<MarkdownWidgetImpl> {
  @override
  Widget build(BuildContext context) {
    return MarkdownWidget(
      data: widget.data,
      config: _getMarkdownConfig(context),
      shrinkWrap: true,
    );
  }

  // 配置 Markdown 样式
  MarkdownConfig _getMarkdownConfig(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MarkdownConfig(
      configs: [
        // 代码块配置
        PreConfig(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(8),
          ),
          language: 'javascript',
          theme: isDark ? a11yDarkTheme : a11yLightTheme,
          padding: const EdgeInsets.all(16),
          textStyle: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 14,
            height: 1.5,
          ),
        ),
        // 内联代码配置
        CodeConfig(
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 14,
            // color: Theme.of(context).primaryColor,
            // backgroundColor: isDark
            //     ? Colors.white.withOpacity(0.1)
            //     : Colors.black.withOpacity(0.05),
          ),
        ),
        // 标题配置
        H1Config(
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        H2Config(
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        H3Config(
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        // 链接配置
        LinkConfig(
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            decoration: TextDecoration.underline,
          ),
          onTap: (url) {
            // 处理链接点击
            _launchUrl(url);
          },
        ),
        // // 列表配置
        // ListConfig(
        //   marker: const TextSpan(text: '• '),
        //   padding: const EdgeInsets.only(left: 24),
        // ),
        // 表格配置
        TableConfig(
          border: TableBorder.all(
            color: Colors.grey.withOpacity(0.3),
            width: 1,
          ),
          headerStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
      // 基础文本样式
      // textConfig: TextConfig(
      //   text: TextStyle(
      //     fontSize: 16,
      //     color: isDark ? Colors.white : Colors.black87,
      //     height: 1.5,
      //   ),
      // ),
    );
  }


  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      throw Exception('无法打开链接: $url');
    }
  }
}