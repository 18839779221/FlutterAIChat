import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/widgets/tool_call/tool_result_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolResultCardWidget', () {
    testWidgets('renders success summary', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ToolResultCardWidget(
              result: ToolResult(
                toolName: 'fetch_webpage',
                status: ToolExecutionStatus.success,
                summary: '已读取网页',
              ),
            ),
          ),
        ),
      );

      expect(find.text('工具执行完成'), findsOneWidget);
      expect(find.text('已读取网页'), findsOneWidget);
    });

    testWidgets('renders failure summary and error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ToolResultCardWidget(
              result: ToolResult(
                toolName: 'create_reminder',
                status: ToolExecutionStatus.failure,
                summary: '创建提醒失败',
                errorMessage: 'unsupported_tool',
              ),
            ),
          ),
        ),
      );

      expect(find.text('工具执行失败'), findsOneWidget);
      expect(find.text('创建提醒失败'), findsOneWidget);
      expect(find.text('错误：unsupported_tool'), findsOneWidget);
    });
  });
}
