import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_confirmation/tool_confirmation_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolConfirmationBottomBar', () {
    testWidgets('renders invocation summary and three actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ToolConfirmationBottomBar(
              message: ChatMessage(
                id: 1,
                text: '准备执行工具',
                role: MessageRole.assistant,
              ),
              invocation: const ToolInvocation(
                toolName: 'Write',
                arguments: {'file_path': 'draft.md'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '准备写入 draft.md',
                requiresConfirmation: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('写入文件'), findsOneWidget);
      expect(find.text('准备写入 draft.md'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('继续，以后不再确认'), findsOneWidget);
    });

    testWidgets('invokes callbacks from all action buttons', (tester) async {
      var continued = false;
      var cancelled = false;
      var trusted = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ToolConfirmationBottomBar(
              message: ChatMessage(
                id: 1,
                text: '准备执行工具',
                role: MessageRole.assistant,
              ),
              invocation: const ToolInvocation(
                toolName: 'Edit',
                arguments: {'file_path': 'main.dart'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '准备编辑 main.dart',
                requiresConfirmation: true,
              ),
              onContinue: () => continued = true,
              onCancel: () => cancelled = true,
              onContinueAndTrust: () => trusted = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('继续'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.tap(find.text('继续，以后不再确认'));
      await tester.pump();

      expect(continued, isTrue);
      expect(cancelled, isTrue);
      expect(trusted, isTrue);
    });
  });
}
