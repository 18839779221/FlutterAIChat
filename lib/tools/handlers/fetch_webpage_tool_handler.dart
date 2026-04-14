import '../../models/chat_message.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles the complete runtime behavior for the `fetch_webpage` tool.
class FetchWebpageToolHandler implements ToolHandler {
  FetchWebpageToolHandler({
    required WebpageFetcher webpageFetcher,
  }) : _webpageFetcher = webpageFetcher;

  final WebpageFetcher _webpageFetcher;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'fetch_webpage',
        title: '读取网页',
        description: '读取网页正文并返回可供总结的文本内容。',
        descriptionForModel:
            '当用户已经提供 URL，或者搜索结果里已经有明确网页链接，需要直接读取网页正文时使用。不要把它用于“先去网上找资料”的场景；那种情况应先用 web_search。',
        category: ToolCategory.retrieval,
        capabilities: [ToolCapability.webUrlReader],
        whenToUse: [
          '用户消息里已经包含 URL',
          '上一轮工具结果已经给出了明确网页链接，需要继续打开读取',
        ],
        whenNotToUse: [
          '用户只是笼统要求联网查资料，但没有给 URL',
          '问题只依赖聊天记录，不需要网页内容',
        ],
        parameters: {
          'url': 'string',
          'extractMode': 'string?',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'url': ToolArgumentProperty.string(
              description: '要读取的网页链接。',
              format: 'uri',
            ),
            'extractMode': ToolArgumentProperty.string(
              description: '可选的正文提取模式；不确定时留空。',
            ),
          },
          required: ['url'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final url = rawArguments['url'];
    if (url is! String || url.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_url',
        errorSummary: '读取网页失败：缺少有效链接',
      );
    }

    final extractMode = rawArguments['extractMode'];
    return ToolArgumentResolution.valid({
      'url': url.trim(),
      if (extractMode is String && extractMode.trim().isNotEmpty)
        'extractMode': extractMode.trim(),
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _webpageFetcher(
      url: context.arguments['url'] as String,
      extractMode: context.arguments['extractMode'] as String?,
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

    final payload = toolResult.payload;
    if (payload['title'] is String &&
        (payload['title'] as String).trim().isNotEmpty) {
      buffer.writeln('网页标题：${payload['title']}');
    }
    if (payload['url'] is String &&
        (payload['url'] as String).trim().isNotEmpty) {
      buffer.writeln('网页链接：${payload['url']}');
    }

    final content = (payload['content'] ?? '').toString().trim();
    if (content.isNotEmpty) {
      buffer.writeln('网页正文：${_truncateContextText(content, maxLength: 1200)}');
    } else if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    return buffer.toString().trim();
  }

  String _truncateContextText(
    String value, {
    required int maxLength,
  }) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}
