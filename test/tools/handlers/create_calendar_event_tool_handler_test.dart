import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/handlers/create_calendar_event_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateCalendarEventToolHandler', () {
    test('normalizes startAt and endAt from relative tomorrow intent', () async {
      final handler = CreateCalendarEventToolHandler(
        calendarEventCreator: ({
          required title,
          required startAt,
          endAt,
          location,
          notes,
        }) async =>
            ToolResult(
          toolName: 'create_calendar_event',
          status: ToolExecutionStatus.success,
          summary: '已创建日历事件：$title',
          data: {
            'title': title,
            'startAt': startAt,
            'endAt': endAt,
          },
        ),
        nowProvider: () => DateTime.parse('2026-03-31T09:00:00+08:00'),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'title': '项目评审',
          'startAt': '2025-02-14T15:00:00+08:00',
          'endAt': '2025-02-14T16:30:00+08:00',
        },
        userMessage: '明天下午三点到四点半创建项目评审',
        history: const [],
        now: DateTime.parse('2026-03-31T09:00:00+08:00'),
      );

      expect(resolution.isValid, isTrue);
      expect(
        resolution.normalizedArguments['startAt'],
        '2026-04-01T15:00:00+08:00',
      );
      expect(
        resolution.normalizedArguments['endAt'],
        '2026-04-01T16:30:00+08:00',
      );
    });
  });
}
