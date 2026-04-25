import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_result_card.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fetch_webpage tool cards', () {
    testWidgets('workflow card shows host and prompt summary', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FetchWebpageToolWorkflowCard(
              steps: [
                ToolWorkflowStep(
                  stepId: 'fetch-1',
                  turnId: 'turn-1',
                  toolName: 'fetch_webpage',
                  title: '读取网页',
                  summary: '准备读取网页',
                  status: ToolWorkflowStepStatus.running,
                  requiresConfirmation: false,
                  details: {
                    'url': 'https://flutter.dev/docs',
                    'prompt': '提取和键盘焦点丢失相关的信息',
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('读取网页'), findsOneWidget);
      expect(find.text('阅读网页 · flutter.dev'), findsOneWidget);
      expect(find.textContaining('键盘焦点丢失'), findsOneWidget);
      expect(find.text('https://flutter.dev/docs'), findsNothing);
    });

    testWidgets(
        'result card collapsed state shows host prompt and result preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FetchWebpageToolResultCard(
              result: ToolResult(
                toolName: 'fetch_webpage',
                status: ToolExecutionStatus.success,
                summary: '已返回网页处理结果',
                data: {
                  'url': 'https://flutter.dev/docs',
                  'host': 'flutter.dev',
                  'prompt': '提取和焦点丢失相关的信息',
                  'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
                  'processedContent': '页面提到频繁 rebuild 可能导致焦点丢失，并建议减少输入节点被替换的次数。',
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('阅读网页 · flutter.dev'), findsOneWidget);
      expect(find.textContaining('焦点丢失'), findsWidgets);
      expect(find.textContaining('频繁 rebuild'), findsOneWidget);
    });

    testWidgets(
        'result card expanded state shows Prompt and processed content sections',
        (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FetchWebpageToolResultCard(
              result: ToolResult(
                toolName: 'fetch_webpage',
                status: ToolExecutionStatus.success,
                summary: '已返回网页处理结果',
                data: {
                  'url': 'https://flutter.dev/docs',
                  'host': 'flutter.dev',
                  'prompt': '提取和焦点丢失相关的信息',
                  'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
                  'processedContent': '页面提到频繁 rebuild 可能导致焦点丢失，并建议减少输入节点被替换的次数。',
                  'rawExcerpt': 'When the input node is replaced too often...',
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('阅读网页 · flutter.dev'));
      await tester.pumpAndSettle();

      expect(find.text('Prompt'), findsOneWidget);
      expect(find.text('处理结果'), findsOneWidget);
      expect(find.text('来源与细节'), findsOneWidget);
      expect(find.textContaining('When the input node'), findsOneWidget);
    });
  });
}
