import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/shared/highlighted_code_content.dart';
import 'package:ai_chat/widgets/tool_renderers/file_change_preview.dart';
import 'package:ai_chat/widgets/tool_renderers/write_tool_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Write tool cards', () {
    testWidgets('result card shows file path and compact status only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WriteToolResultCard(
              result: ToolResult(
                toolName: 'Write',
                status: ToolExecutionStatus.success,
                summary: '已写入文件：docs/plan.md',
                data: {
                  'filePath': 'docs/plan.md',
                  'filePreviouslyExisted': false,
                  'oldLength': 0,
                  'newLength': 120,
                  'oldContentPreview': '',
                  'newContentPreview':
                      'line 1\nline 2\nnew file body\nline 4\nline 5',
                  'fileVersion': {
                    'modifiedAt': '2026-04-22T10:00:00.000',
                  },
                  'postWriteData': {
                    'formatted': true,
                  },
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('已新建'), findsOneWidget);
      expect(find.text('docs/plan.md'), findsOneWidget);
      expect(find.text('WRITE'), findsNothing);
      expect(find.text('新建文件'), findsNothing);
      expect(find.text('0 -> 120 字符'), findsNothing);
      expect(find.text('已写入文件：docs/plan.md'), findsNothing);
      expect(find.text('查看详情'), findsNothing);
      expect(find.text('postWriteData'), findsNothing);
      expect(find.text('formatted: true'), findsNothing);
      expect(find.byType(FileChangePreview), findsOneWidget);
    });

    testWidgets('result card falls back to inline row when preview is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WriteToolResultCard(
              result: ToolResult(
                toolName: 'Write',
                status: ToolExecutionStatus.success,
                summary: '已写入文件：docs/plan.md',
                data: {
                  'filePath': 'docs/plan.md',
                  'filePreviouslyExisted': true,
                  'newLength': 120,
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
      expect(find.text('已写入'), findsNothing);
      expect(find.byType(FileChangePreview), findsNothing);
    });

    testWidgets('failure result uses failure wording instead of success wording', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WriteToolResultCard(
              result: ToolResult(
                toolName: 'Write',
                status: ToolExecutionStatus.failure,
                summary: '写入文件失败',
                data: {
                  'filePath': 'docs/plan.md',
                },
                errorMessage: 'write_failed',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
      expect(find.text('写入失败'), findsOneWidget);
      expect(find.text('已写入'), findsNothing);
      expect(find.text('已新建'), findsNothing);
    });

    testWidgets('result card reuses compact file change preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WriteToolResultCard(
              result: ToolResult(
                toolName: 'Write',
                status: ToolExecutionStatus.success,
                summary: '已写入文件：docs/plan.md',
                data: {
                  'filePath': 'docs/plan.md',
                  'filePreviouslyExisted': true,
                  'oldLength': 58,
                  'newLength': 58,
                  'oldContentPreview':
                      'header 1\nheader 2\nconst oldValue = 1;\nprint(oldValue);\nfooter 1\nfooter 2',
                  'newContentPreview':
                      'header 1\nheader 2\nconst newValue = 2;\nprint(newValue);\nfooter 1\nfooter 2',
                  'contentPreviewTruncated': false,
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('已写入'), findsOneWidget);
      expect(find.text('docs/plan.md'), findsOneWidget);
      expect(find.byType(FileChangePreview), findsOneWidget);
      expect(_findCode('header 1'), findsOneWidget);
      expect(_findCode('const oldValue = 1;'), findsOneWidget);
      expect(_findCode('const newValue = 2;'), findsOneWidget);
      expect(_findCode('print(oldValue);'), findsOneWidget);
      expect(_findCode('print(newValue);'), findsOneWidget);
      expect(_findCode('footer 1'), findsWidgets);
      expect(_findCode('footer 2'), findsOneWidget);
    });
  });
}

Finder _findCode(String code) {
  return find.byWidgetPredicate(
    (widget) => widget is HighlightedCodeContent && widget.code == code,
  );
}
