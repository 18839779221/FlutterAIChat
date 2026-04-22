import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
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
          find.text('最近一次编辑：test/main_test.dart，共发生 2 次编辑动作'), findsOneWidget);
      expect(find.text('这次编辑一共执行了 2 次替换动作'), findsOneWidget);
      expect(find.text('步骤 1'), findsOneWidget);
      expect(find.text('步骤 2'), findsOneWidget);
      expect(find.text('全量替换 -> lib/main.dart'), findsOneWidget);
      expect(find.text('单次替换 -> test/main_test.dart'), findsOneWidget);
      expect(find.text('把 "old text" 替换为 "new text"'), findsOneWidget);
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

      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('替换 2 处'), findsOneWidget);
      expect(find.text('300 -> 316 字符'), findsOneWidget);
      expect(find.text('old text'), findsNothing);

      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();

      expect(find.text('old text'), findsOneWidget);
      expect(find.text('new text'), findsOneWidget);
    });
  });
}
