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
              expanded: false,
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

    testWidgets('workflow card supports inline expand for single completed step', (
      tester,
    ) async {
      final expanded = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: expanded,
              builder: (context, isExpanded, child) {
                return FetchWebpageToolWorkflowCard(
                  expanded: isExpanded,
                  onTap: () => expanded.value = !expanded.value,
                  steps: const [
                    ToolWorkflowStep(
                      stepId: 'fetch-1',
                      turnId: 'turn-1',
                      toolName: 'fetch_webpage',
                      title: '读取网页',
                      summary: '已返回网页处理结果',
                      status: ToolWorkflowStepStatus.completed,
                      requiresConfirmation: false,
                      details: {
                        'url': 'https://flutter.dev/docs',
                        'prompt': '提取和焦点丢失相关的信息',
                        'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('阅读网页 · flutter.dev'));
      await tester.pumpAndSettle();

      expect(find.text('网页详情'), findsOneWidget);
      expect(find.text('flutter.dev'), findsWidgets);
      expect(find.textContaining('焦点丢失'), findsWidgets);
    });

    testWidgets('workflow card supports batch expand for multiple steps', (
      tester,
    ) async {
      final expanded = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: expanded,
              builder: (context, isExpanded, child) {
                return FetchWebpageToolWorkflowCard(
                  expanded: isExpanded,
                  onTap: () => expanded.value = !expanded.value,
                  steps: const [
                    ToolWorkflowStep(
                      stepId: 'fetch-1',
                      turnId: 'turn-1',
                      toolName: 'fetch_webpage',
                      title: '读取网页',
                      summary: '已返回网页处理结果',
                      status: ToolWorkflowStepStatus.completed,
                      requiresConfirmation: false,
                      details: {
                        'url': 'https://flutter.dev/docs',
                        'prompt': '总结 Flutter 页面',
                        'resultPreview': 'Flutter 摘要',
                      },
                    ),
                    ToolWorkflowStep(
                      stepId: 'fetch-2',
                      turnId: 'turn-1',
                      toolName: 'fetch_webpage',
                      title: '读取网页',
                      summary: '读取失败：http_403',
                      status: ToolWorkflowStepStatus.failed,
                      requiresConfirmation: false,
                      details: {
                        'url': 'https://example.com/post',
                        'prompt': '总结 Example 页面',
                        'failureReason': 'http_403',
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('读取网页 · 2 个目标'));
      await tester.pumpAndSettle();

      expect(find.text('本批共 2 个网页'), findsOneWidget);
      expect(find.text('flutter.dev'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.textContaining('http_403'), findsOneWidget);
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
                  'processedContent':
                      '页面提到频繁 rebuild 可能导致焦点丢失，并建议减少输入节点被替换的次数。',
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('阅读网页 · flutter.dev'), findsOneWidget);
      expect(find.textContaining('焦点丢失'), findsWidgets);
      expect(find.textContaining('频繁 rebuild'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
    });

    testWidgets(
        'result card opens bottom sheet and shows markdown content sections',
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
                  'processedContent':
                      '## Heading\n\n- item 1\n- item 2\n\n页面提到频繁 rebuild 可能导致焦点丢失，并建议减少输入节点被替换的次数。',
                  'rawExcerpt': 'When the input node is replaced too often...',
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('阅读网页 · flutter.dev'));
      await tester.pumpAndSettle();

      expect(find.text('flutter.dev'), findsWidgets);
      expect(find.text('Prompt'), findsOneWidget);
      expect(find.text('处理结果'), findsOneWidget);
      expect(find.text('来源与细节'), findsOneWidget);
      expect(find.text('Heading'), findsOneWidget);
      expect(find.text('item 1'), findsOneWidget);
      expect(find.textContaining('When the input node'), findsOneWidget);
    });
  });
}
