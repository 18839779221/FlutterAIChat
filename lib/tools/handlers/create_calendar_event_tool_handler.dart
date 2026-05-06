import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_datetime_normalizer.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles validation, normalization, execution, and context building for
/// `create_calendar_event`.
class CreateCalendarEventToolHandler implements ToolHandler {
  CreateCalendarEventToolHandler({
    required CalendarEventCreator calendarEventCreator,
    DateTime Function()? nowProvider,
  })  : _calendarEventCreator = calendarEventCreator,
        _nowProvider = nowProvider ?? DateTime.now;

  final CalendarEventCreator _calendarEventCreator;
  final DateTime Function() _nowProvider;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'create_calendar_event',
        title: 'Create Calendar Event',
        localizedTitle: LocalizedToolText(
          english: 'Create Calendar Event',
          chinese: '创建日历事件',
        ),
        descriptionForModel:
            'Use this when the user explicitly asks to schedule something, create a calendar event, or add something to the calendar. It must have a title and start time; end time, location, and notes are optional. This tool writes to the system calendar, so it is a high-risk mutating action and requires confirmation.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this when the user explicitly asks to schedule something, create a calendar event, or add something to the calendar. It must have a title and start time; end time, location, and notes are optional. This tool writes to the system calendar, so it is a high-risk mutating action and requires confirmation.',
          chinese:
              '当用户明确要求安排日程、创建日历事件或加入日历时使用。必须具备标题和开始时间；结束时间、地点、备注可选。该工具会写入系统日历，属于高风险写操作，需要确认。',
        ),
        parameters: {
          'title': 'string',
          'startAt': 'string',
          'endAt': 'string?',
          'location': 'string?',
          'notes': 'string?',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'title': ToolArgumentProperty.string(
              description: 'Calendar event title.',
              localizedDescription: LocalizedToolText(
                english: 'Calendar event title.',
                chinese: '日历事件标题。',
              ),
            ),
            'startAt': ToolArgumentProperty.string(
              description:
                  'Event start time, ideally as an ISO datetime string or another explicit date and time.',
              localizedDescription: LocalizedToolText(
                english:
                    'Event start time, ideally as an ISO datetime string or another explicit date and time.',
                chinese: '事件开始时间，建议使用 ISO 时间字符串或明确的日期时间。',
              ),
              format: 'date-time',
            ),
            'endAt': ToolArgumentProperty.string(
              description: 'Optional event end time.',
              localizedDescription: LocalizedToolText(
                english: 'Optional event end time.',
                chinese: '可选的结束时间。',
              ),
              format: 'date-time',
            ),
            'location': ToolArgumentProperty.string(
              description: 'Optional event location.',
              localizedDescription: LocalizedToolText(
                english: 'Optional event location.',
                chinese: '可选的地点信息。',
              ),
            ),
            'notes': ToolArgumentProperty.string(
              description: 'Optional notes with extra agenda details.',
              localizedDescription: LocalizedToolText(
                english: 'Optional notes with extra agenda details.',
                chinese: '可选备注，用于补充议程细节。',
              ),
            ),
          },
          required: ['title', 'startAt'],
        ),
        requiresConfirmation: true,
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final title = rawArguments['title'];
    final startAt = rawArguments['startAt'];
    if (title is! String || title.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_title',
        errorSummary: '创建日历事件失败：缺少有效标题',
      );
    }
    if (startAt is! String || startAt.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_start_at',
        errorSummary: '创建日历事件失败：缺少开始时间',
      );
    }

    var normalizedStartAt = startAt.trim();
    final endAt = rawArguments['endAt'] as String?;
    var normalizedEndAt = endAt?.trim();
    final relativeOffsetDays = extractRelativeDayOffset(userMessage);
    if (relativeOffsetDays != null) {
      normalizedStartAt = normalizeRelativeIsoDate(
            rawIsoText: normalizedStartAt,
            dayOffset: relativeOffsetDays,
            anchor: _nowProvider(),
          ) ??
          normalizedStartAt;
      normalizedEndAt = normalizedEndAt == null
          ? null
          : normalizeRelativeIsoDate(
                rawIsoText: normalizedEndAt,
                dayOffset: relativeOffsetDays,
                anchor: _nowProvider(),
              ) ??
              normalizedEndAt;
    }

    if (DateTime.tryParse(normalizedStartAt) == null) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_start_at',
        errorSummary: '创建日历事件失败：开始时间格式无效',
      );
    }
    if (normalizedEndAt != null && DateTime.tryParse(normalizedEndAt) == null) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_end_at',
        errorSummary: '创建日历事件失败：结束时间格式无效',
      );
    }

    return ToolArgumentResolution.valid({
      'title': title.trim(),
      'startAt': normalizedStartAt,
      if (normalizedEndAt != null) 'endAt': normalizedEndAt,
      if (rawArguments['location'] is String)
        'location': rawArguments['location'],
      if (rawArguments['notes'] is String) 'notes': rawArguments['notes'],
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _calendarEventCreator(
      title: context.arguments['title'] as String,
      startAt: context.arguments['startAt'] as String,
      endAt: context.arguments['endAt'] as String?,
      location: context.arguments['location'] as String?,
      notes: context.arguments['notes'] as String?,
    );
  }

}
