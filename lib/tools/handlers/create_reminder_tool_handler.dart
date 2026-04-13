import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_datetime_normalizer.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles validation, normalization, execution, and context building for
/// `create_reminder`.
class CreateReminderToolHandler implements ToolHandler {
  CreateReminderToolHandler({
    required ReminderCreator reminderCreator,
    DateTime Function()? nowProvider,
  })  : _reminderCreator = reminderCreator,
        _nowProvider = nowProvider ?? DateTime.now;

  final ReminderCreator _reminderCreator;
  final DateTime Function() _nowProvider;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        description: '创建系统提醒事项。',
        descriptionForModel:
            '当用户明确要求创建提醒、闹钟或待办提醒时使用。必须具备标题和提醒时间；如果时间缺失，应先继续确认，不要盲目调用。该工具会触发系统侧写操作，需要确认。',
        category: ToolCategory.productivity,
        capabilities: [ToolCapability.reminderCreate],
        whenToUse: [
          '用户要求提醒我、到时候叫我、帮我设提醒',
        ],
        whenNotToUse: [
          '用户没有明确要求创建提醒',
          '缺少可解析的提醒时间',
        ],
        parameters: {
          'title': 'string',
          'dueAt': 'string?',
          'note': 'string?',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'title': ToolArgumentProperty.string(
              description: '提醒标题，说明需要提醒的事项。',
            ),
            'dueAt': ToolArgumentProperty.string(
              description: '提醒时间，建议使用 ISO 时间字符串或可被系统解析的明确时间。',
              format: 'date-time',
            ),
            'note': ToolArgumentProperty.string(
              description: '可选备注，用于补充提醒细节。',
            ),
          },
          required: ['title', 'dueAt'],
        ),
        requiresConfirmation: true,
        riskLevel: 'medium',
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final title = rawArguments['title'];
    final dueAt = rawArguments['dueAt'];
    if (title is! String || title.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_title',
        errorSummary: '创建提醒失败：缺少有效标题',
      );
    }
    if (dueAt is! String || dueAt.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_due_at',
        errorSummary: '创建提醒失败：缺少有效时间',
      );
    }

    var normalizedDueAt = dueAt.trim();
    final relativeOffsetDays = extractRelativeDayOffset(userMessage);
    final normalizedNaturalLanguageDueAt = normalizeNaturalLanguageDateTime(
      rawText: normalizedDueAt,
      anchor: _nowProvider(),
      fallbackDayOffset: relativeOffsetDays,
    );
    if (normalizedNaturalLanguageDueAt != null) {
      normalizedDueAt = normalizedNaturalLanguageDueAt;
    } else if (relativeOffsetDays != null) {
      normalizedDueAt = normalizeRelativeIsoDate(
            rawIsoText: normalizedDueAt,
            dayOffset: relativeOffsetDays,
            anchor: _nowProvider(),
          ) ??
          normalizedDueAt;
    }

    if (DateTime.tryParse(normalizedDueAt) == null) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_due_at',
        errorSummary: '创建提醒失败：时间格式无效',
      );
    }

    return ToolArgumentResolution.valid({
      'title': title.trim(),
      'dueAt': normalizedDueAt,
      if (rawArguments['note'] is String) 'note': rawArguments['note'],
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _reminderCreator(
      title: context.arguments['title'] as String,
      dueAt: context.arguments['dueAt'] as String?,
      note: context.arguments['note'] as String?,
    );
  }

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: '提醒工具执行结果：${result.summary}',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }
}
