import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_renderers/generate_image_tool_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generate_image tool cards', () {
    testWidgets('workflow card shows prompt summary and model provider line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: GenerateImageToolWorkflowCard(
              steps: [
                ToolWorkflowStep(
                  stepId: 'img-1',
                  turnId: 'turn-1',
                  toolName: 'generate_image',
                  title: '生成图片',
                  summary: '准备生成图片',
                  status: ToolWorkflowStepStatus.running,
                  requiresConfirmation: false,
                  details: {
                    'prompt': 'A cinematic whale floating above a neon city',
                    'model': 'gpt-image-2',
                    'provider': 'beehears',
                    'size': '1024x1024',
                    'quality': 'high',
                  },
                ),
              ],
              isExpanded: false,
            ),
          ),
        ),
      );

      expect(find.text('生成图片'), findsWidgets);
      expect(find.textContaining('cinematic whale'), findsOneWidget);
      expect(find.text('gpt-image-2 (beehears)'), findsOneWidget);
      expect(find.text('Size：1024x1024'), findsNothing);

      final promptText = tester.widget<Text>(
        find.textContaining('cinematic whale'),
      );
      expect(promptText.maxLines, 2);
      expect(promptText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('workflow card expanded state shows parameter details', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: GenerateImageToolWorkflowCard(
              steps: [
                ToolWorkflowStep(
                  stepId: 'img-1',
                  turnId: 'turn-1',
                  toolName: 'generate_image',
                  title: '生成图片',
                  summary: '准备生成图片',
                  status: ToolWorkflowStepStatus.completed,
                  requiresConfirmation: false,
                  details: {
                    'prompt': 'A cinematic whale floating above a neon city',
                    'model': 'gpt-image-2',
                    'provider': 'beehears',
                    'size': '1024x1024',
                    'quality': 'high',
                    'background': 'transparent',
                  },
                ),
              ],
              isExpanded: true,
            ),
          ),
        ),
      );

      expect(find.text('Prompt'), findsOneWidget);
      expect(find.text('输入参数'), findsOneWidget);
      expect(_findRichTextContaining('Size：1024x1024'), findsOneWidget);
      expect(_findRichTextContaining('Quality：high'), findsOneWidget);
      expect(_findRichTextContaining('Background：transparent'), findsOneWidget);
    });

    testWidgets('result card toggles parameter details inline', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: GenerateImageToolResultCard(
              result: ToolResult(
                toolName: 'generate_image',
                status: ToolExecutionStatus.success,
                summary: '已生成图片',
                data: {
                  'prompt': 'A cinematic whale floating above a neon city',
                  'model': 'gpt-image-2',
                  'provider': 'beehears',
                  'size': '1024x1024',
                  'quality': 'high',
                  'generatedImages': const [
                    {'fileName': 'generated-image-1.png'},
                  ],
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('已生成图片'), findsOneWidget);
      expect(find.text('共生成 1 张图片'), findsOneWidget);
      expect(find.text('gpt-image-2 (beehears)'), findsOneWidget);
      expect(find.textContaining('Model：gpt-image-2 (beehears)'), findsNothing);

      final promptText = tester.widget<Text>(
        find.textContaining('cinematic whale'),
      );
      expect(promptText.maxLines, 2);
      expect(promptText.overflow, TextOverflow.ellipsis);

      await tester.tap(find.byType(GenerateImageToolResultCard));
      await tester.pumpAndSettle();

      expect(find.text('Prompt'), findsOneWidget);
      expect(_findRichTextContaining('Size：1024x1024'), findsOneWidget);
      expect(_findRichTextContaining('Quality：high'), findsOneWidget);
      expect(_findRichTextContaining('Count：1'), findsOneWidget);
    });
  });
}

Finder _findRichTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) {
      return false;
    }
    return widget.text.toPlainText().contains(text);
  });
}
