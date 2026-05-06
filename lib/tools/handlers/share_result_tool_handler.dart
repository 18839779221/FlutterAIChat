import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles the complete runtime behavior for the `share_result` tool.
class ShareResultToolHandler implements ToolHandler {
  ShareResultToolHandler({
    required ResultSharer resultSharer,
  }) : _resultSharer = resultSharer;

  final ResultSharer _resultSharer;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'share_result',
        title: 'Share Result',
        localizedTitle: LocalizedToolText(
          english: 'Share Result',
          chinese: '分享结果',
        ),
        descriptionForModel:
            'Use this when the user explicitly asks to share, send, or forward a result to another app. It opens the system share sheet and is an output action. If the user only wants to view the result, do not call it automatically.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Use this when the user explicitly asks to share, send, or forward a result to another app. It opens the system share sheet and is an output action. If the user only wants to view the result, do not call it automatically.',
          chinese:
              '当用户明确要求把结果分享、发送、转发到其他应用时使用。它会打开系统分享面板，属于输出动作；如果用户只是想查看结果，不要自动调用。',
        ),
        parameters: {
          'text': 'string',
          'subject': 'string?',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'text': ToolArgumentProperty.string(
              description: 'Main body text to share.',
              localizedDescription: LocalizedToolText(
                english: 'Main body text to share.',
                chinese: '要分享的正文内容。',
              ),
            ),
            'subject': ToolArgumentProperty.string(
              description: 'Optional share subject.',
              localizedDescription: LocalizedToolText(
                english: 'Optional share subject.',
                chinese: '可选分享主题。',
              ),
            ),
          },
          required: ['text'],
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
    final text = rawArguments['text'];
    if (text is! String || text.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_text',
        errorSummary: '分享结果失败：缺少有效内容',
      );
    }

    final subject = rawArguments['subject'];
    return ToolArgumentResolution.valid({
      'text': text.trim(),
      if (subject is String && subject.trim().isNotEmpty)
        'subject': subject.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _resultSharer(
      text: context.arguments['text'] as String,
      subject: context.arguments['subject'] as String?,
    );
  }
}
