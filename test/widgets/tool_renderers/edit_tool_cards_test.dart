import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/shared/highlighted_code_content.dart';
import 'package:ai_chat/widgets/technical_content_surface.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_result_card.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_workflow_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Edit tool cards', () {
    testWidgets('workflow card summarizes latest edit and expands full history',
        (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: EditToolWorkflowCard(
              isExpanded: true,
              steps: [
                ToolWorkflowStep(
                  stepId: 'edit-1',
                  turnId: 'turn-1',
                  toolName: 'Edit',
                  title: '编辑文件',
                  summary: '准备编辑 lib/main.dart',
                  status: ToolWorkflowStepStatus.failed,
                  requiresConfirmation: false,
                  details: {
                    'file_path': 'lib/main.dart',
                    'old_string': 'old text',
                    'new_string': 'new text',
                    'replace_all': true,
                  },
                ),
                ToolWorkflowStep(
                  stepId: 'edit-2',
                  turnId: 'turn-1',
                  toolName: 'Edit',
                  title: '编辑文件',
                  summary: '准备编辑 test/main_test.dart',
                  status: ToolWorkflowStepStatus.running,
                  requiresConfirmation: false,
                  details: {
                    'file_path': 'test/main_test.dart',
                    'old_string': 'expect(old)',
                    'new_string': 'expect(new)',
                    'replace_all': false,
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('编辑文件'), findsOneWidget);
      expect(
        find.text('最近一次编辑：test/main_test.dart，共发生 2 次编辑动作'),
        findsOneWidget,
      );
      expect(find.text('这次编辑一共执行了 2 次替换动作'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('test/main_test.dart'), findsOneWidget);
      expect(find.text('步骤 1'), findsNothing);
      expect(find.text('步骤 2'), findsNothing);
      expect(find.text('全量替换 -> lib/main.dart'), findsNothing);
      expect(find.text('单次替换 -> test/main_test.dart'), findsNothing);
      expect(find.text('把 "old text" 替换为 "new text"'), findsNothing);
    });

    testWidgets('workflow card previews proposed edit diff when expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: EditToolWorkflowCard(
              isExpanded: true,
              steps: [
                ToolWorkflowStep(
                  stepId: 'edit-1',
                  turnId: 'turn-1',
                  toolName: 'Edit',
                  title: '编辑文件',
                  summary: '准备编辑 hobby.txt',
                  status: ToolWorkflowStepStatus.awaitingConfirmation,
                  requiresConfirmation: true,
                  details: {
                    'file_path': 'hobby.txt',
                    'old_string': '我的爱好是足球。',
                    'new_string': '我的爱好是打篮球。',
                    'replace_all': false,
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('-'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is HighlightedCodeContent &&
              widget.code == '我的爱好是足球。',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is HighlightedCodeContent &&
              widget.code == '我的爱好是打篮球。',
        ),
        findsOneWidget,
      );
      expect(find.text('hobby.txt'), findsOneWidget);
      expect(find.text('步骤 1'), findsNothing);
      expect(find.byType(TechnicalContentSurface), findsOneWidget);
    });

    testWidgets(
        'result card shows replacement count first and snippets after expand',
        (tester) async {
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
                  'oldString': 'old text',
                  'newString': 'new text',
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('EDIT'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('替换 2 处'), findsOneWidget);
      expect(find.text('300 -> 316 字符'), findsOneWidget);
      expect(find.text('old text'), findsNothing);

      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();

      expect(find.text('old text'), findsOneWidget);
      expect(find.text('new text'), findsOneWidget);
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
                  'oldLength': 26,
                  'newLength': 26,
                  'oldContentPreview': 'final value = old;\nprint(value);',
                  'newContentPreview': 'final value = new;\nprint(value);',
                  'contentPreviewTruncated': false,
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('EDIT'), findsOneWidget);
      expect(find.byType(HighlightedCodeContent), findsWidgets);
      expect(find.text('-'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is HighlightedCodeContent &&
              widget.code == 'final value = old;',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is HighlightedCodeContent &&
              widget.code == 'final value = new;',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is HighlightedCodeContent &&
              widget.code == 'print(value);',
        ),
        findsWidgets,
      );
    });
  });
}
