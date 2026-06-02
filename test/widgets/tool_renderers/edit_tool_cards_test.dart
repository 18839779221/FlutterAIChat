import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/shared/highlighted_code_content.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_result_card.dart';
import 'package:ai_chat/widgets/tool_renderers/file_change_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Edit tool cards', () {
    testWidgets('result card shows file path and compact status only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: EditToolResultCard(
              result: ToolResult(
                toolName: 'Edit',
                status: ToolExecutionStatus.success,
                summary: '已编辑文件：lib/main.dart',
                data: {
                  'filePath': 'lib/main.dart',
                  'replacementCount': 2,
                  'oldLength': 300,
                  'newLength': 316,
                  'oldContentPreview':
                      'before 1\nbefore 2\nold text\nafter 1\nafter 2',
                  'newContentPreview':
                      'before 1\nbefore 2\nnew text\nafter 1\nafter 2',
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('已修改'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('EDIT'), findsNothing);
      expect(find.text('替换 2 处'), findsNothing);
      expect(find.text('300 -> 316 字符'), findsNothing);
      expect(find.text('已编辑文件：lib/main.dart'), findsNothing);
      expect(find.text('查看详情'), findsNothing);
      expect(find.byType(FileChangePreview), findsOneWidget);
    });

    testWidgets('result card falls back to inline row when preview is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: EditToolResultCard(
              result: ToolResult(
                toolName: 'Edit',
                status: ToolExecutionStatus.success,
                summary: '已编辑文件：lib/main.dart',
                data: {
                  'filePath': 'lib/main.dart',
                  'replacementCount': 2,
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
      expect(find.text('已修改'), findsNothing);
      expect(find.byType(FileChangePreview), findsNothing);
    });

    testWidgets('failure result uses failure wording instead of success wording', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: EditToolResultCard(
              result: ToolResult(
                toolName: 'Edit',
                status: ToolExecutionStatus.failure,
                summary: '编辑文件失败：文件未读取或状态已过期',
                data: {
                  'filePath': 'interests.json',
                },
                errorMessage: 'unread_file',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
      expect(find.text('编辑失败'), findsOneWidget);
      expect(find.text('已修改'), findsNothing);
    });

    testWidgets('result card renders a unified diff from preview content', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: EditToolResultCard(
              result: ToolResult(
                toolName: 'Edit',
                status: ToolExecutionStatus.success,
                summary: '已编辑文件：lib/main.dart',
                data: {
                  'filePath': 'lib/main.dart',
                  'replacementCount': 1,
                  'oldLength': 70,
                  'newLength': 70,
                  'oldContentPreview':
                      'line 0\nline 1\nline 2\nfinal value = old;\nprint(oldValue);\nline 5\nline 6\nline 7',
                  'newContentPreview':
                      'line 0\nline 1\nline 2\nfinal value = new;\nprint(newValue);\nline 5\nline 6\nline 7',
                  'contentPreviewTruncated': false,
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('已修改'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('EDIT'), findsNothing);
      expect(find.byType(FileChangePreview), findsOneWidget);
      expect(find.text('-'), findsWidgets);
      expect(find.text('+'), findsWidgets);
      expect(_findCode('line 0'), findsNothing);
      expect(_findCode('line 2'), findsWidgets);
      expect(_findCode('final value = old;'), findsOneWidget);
      expect(_findCode('final value = new;'), findsOneWidget);
      expect(_findCode('print(oldValue);'), findsOneWidget);
      expect(_findCode('print(newValue);'), findsOneWidget);
      expect(_findCode('line 5'), findsWidgets);
      expect(_findCode('line 6'), findsOneWidget);
      expect(_findCode('line 7'), findsNothing);
    });
  });
}

Finder _findCode(String code) {
  return find.byWidgetPredicate(
    (widget) => widget is HighlightedCodeContent && widget.code == code,
  );
}
