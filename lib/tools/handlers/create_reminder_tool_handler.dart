import '../../models/chat_message.dart';
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
        parameters: {
          'title': 'string',
          'dueAt': 'string?',
          'note': 'string?',
        },
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
    if (relativeOffsetDays != null) {
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
