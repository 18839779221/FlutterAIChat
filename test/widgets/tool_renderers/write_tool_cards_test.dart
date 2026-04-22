import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_renderers/write_tool_result_card.dart';
import 'package:ai_chat/widgets/tool_renderers/write_tool_workflow_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Write tool cards', () {
    testWidgets(
        'workflow card summarizes latest write and expands full history', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WriteToolWorkflowCard(
              isExpanded: true,
              steps: [
                ToolWorkflowStep(
                  stepId: 'write-1',
                  turnId: 'turn-1',
                  toolName: 'Write',
                  title: '写入文件',
                  summary: '准备写入 docs/plan.md',
                  status: ToolWorkflowStepStatus.completed,
                  requiresConfirmation: false,
                  details: {
                    'file_path': 'docs/plan.md',
                    'content': '# plan',
                  },
                ),
                ToolWorkflowStep(
                  stepId: 'write-2',
                  turnId: 'turn-1',
                  toolName: 'Write',
                  title: '写入文件',
                  summary: '准备写入 docs/tasks.md',
                  status: ToolWorkflowStepStatus.running,
                  requiresConfirmation: false,
                  details: {
                    'file_path': 'docs/tasks.md',
                    'content': '- ship it',
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('写入文件'), findsOneWidget);
      expect(find.text('最近一次写入：docs/tasks.md'), findsOneWidget);
      expect(find.text('这次写入一共进行了 2 次文件操作'), findsOneWidget);
      expect(find.text('步骤 1'), findsOneWidget);
      expect(find.text('步骤 2'), findsOneWidget);
      expect(find.text('整文件写入 1 行 -> docs/plan.md'), findsOneWidget);
      expect(find.text('整文件写入 1 行 -> docs/tasks.md'), findsOneWidget);
    });

    testWidgets('result card shows summary first and evidence after expand', (
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

      expect(find.text('docs/plan.md'), findsOneWidget);
      expect(find.text('新建文件'), findsOneWidget);
      expect(find.text('0 -> 120 字符'), findsOneWidget);
      expect(find.text('postWriteData'), findsNothing);

      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();

      expect(find.text('postWriteData'), findsOneWidget);
      expect(find.text('formatted: true'), findsOneWidget);
    });
  });
}
