import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/widgets/tool_call/tool_confirmation_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolConfirmationCardWidget', () {
    testWidgets('renders three action buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCardWidget(
              invocation: const ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '准备创建提醒：交周报',
                requiresConfirmation: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('继续'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('继续，以后不再确认'), findsOneWidget);
    });

    testWidgets('invokes trust callback from the third button', (tester) async {
      var trustTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCardWidget(
              invocation: const ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '准备创建提醒：交周报',
                requiresConfirmation: true,
              ),
              onContinueAndTrust: () {
                trustTapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('继续，以后不再确认'));
      await tester.pump();

      expect(trustTapped, isTrue);
    });
  });
}
