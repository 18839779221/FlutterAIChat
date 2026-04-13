import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
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
        title: '分享结果',
        description: '调用系统分享面板分享文本结果。',
        descriptionForModel:
            '当用户明确要求把结果分享、发送、转发到其他应用时使用。它会打开系统分享面板，属于输出动作；如果用户只是想查看结果，不要自动调用。',
        category: ToolCategory.outputAction,
        capabilities: [ToolCapability.shareResult],
        whenToUse: [
          '用户明确说分享、发送给别人、导出到外部应用',
        ],
        whenNotToUse: [
          '用户只是想继续阅读或总结内容',
          '用户没有表达对外分享意图',
        ],
        parameters: {
          'text': 'string',
          'subject': 'string?',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'text': ToolArgumentProperty.string(
              description: '要分享的正文内容。',
            ),
            'subject': ToolArgumentProperty.string(
              description: '可选分享主题。',
            ),
          },
          required: ['text'],
        ),
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

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: _buildContextText(result),
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }

  String _buildContextText(ToolResult toolResult) {
    final buffer = StringBuffer()
      ..writeln('以下是工具 `${toolResult.toolName}` 的执行结果，请结合这些信息回答用户。')
      ..writeln('状态：${toolResult.status.name}');

    if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    final payload = toolResult.payload;
    if (payload['subject'] is String &&
        (payload['subject'] as String).trim().isNotEmpty) {
      buffer.writeln('分享主题：${payload['subject']}');
    }
    if (payload['shareStatus'] is String) {
      buffer.writeln('分享状态：${payload['shareStatus']}');
    }

    return buffer.toString().trim();
  }
}
