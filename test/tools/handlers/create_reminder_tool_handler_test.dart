import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/handlers/create_reminder_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateReminderToolHandler', () {
    test('normalizes relative dueAt date from user intent', () async {
      final handler = CreateReminderToolHandler(
        reminderCreator: ({required title, dueAt, note}) async => ToolResult(
          toolName: 'create_reminder',
          status: ToolExecutionStatus.success,
          summary: '已创建提醒：$title',
          data: {'title': title, 'dueAt': dueAt, 'note': note},
        ),
        nowProvider: () => DateTime.parse('2026-03-31T09:00:00+08:00'),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'title': '交周报',
          'dueAt': '2025-02-14T20:00:00+08:00',
        },
        userMessage: '提醒我今天晚上8点交周报',
        history: const [],
        now: DateTime.parse('2026-03-31T09:00:00+08:00'),
      );

      expect(resolution.isValid, isTrue);
      expect(
        resolution.normalizedArguments['dueAt'],
        '2026-03-31T20:00:00+08:00',
      );
    });
  });
}
