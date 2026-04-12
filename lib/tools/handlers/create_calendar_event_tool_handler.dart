import '../../models/chat_message.dart';
import '../../models/tool/tool_definition.dart';
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
        title: '创建日历事件',
        description: '创建系统日历事件。',
        parameters: {
          'title': 'string',
          'startAt': 'string',
          'endAt': 'string?',
          'location': 'string?',
          'notes': 'string?',
        },
        requiresConfirmation: true,
        riskLevel: 'high',
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
      if (rawArguments['location'] is String) 'location': rawArguments['location'],
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

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: '日历工具执行结果：${result.summary}',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }
}
