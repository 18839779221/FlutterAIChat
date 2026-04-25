import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/technical_content_surface.dart';
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
      expect(find.text('docs/plan.md'), findsOneWidget);
      expect(find.text('docs/tasks.md'), findsOneWidget);
      expect(find.text('步骤 1'), findsNothing);
      expect(find.text('步骤 2'), findsNothing);
      expect(find.text('整文件写入 1 行 -> docs/plan.md'), findsNothing);
      expect(find.text('整文件写入 1 行 -> docs/tasks.md'), findsNothing);
    });

    testWidgets('workflow card previews proposed write content when expanded', (
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
                  summary: '准备写入 hobby.txt',
                  status: ToolWorkflowStepStatus.completed,
                  requiresConfirmation: false,
                  details: {
                    'file_path': 'hobby.txt',
                    'content': '我的爱好是打篮球。',
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('+ 我的爱好是打篮球。'), findsOneWidget);
      expect(find.text('hobby.txt'), findsOneWidget);
      expect(find.text('步骤 1'), findsNothing);
      expect(find.textContaining('写入内容预览'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(TechnicalContentSurface), findsOneWidget);
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

    testWidgets('result card previews written content with line numbers', (
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
                  'newLength': 27,
                  'newContentPreview': '# Plan\n- Build preview',
                  'contentPreviewTruncated': false,
                },
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('+ # Plan'), findsOneWidget);
      expect(find.textContaining('+ - Build preview'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });
}
