import '../../models/chat_message.dart';
import '../../models/response/message_content_type.dart';
import '../../models/tool/tool_definition.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles the complete runtime behavior for the `web_search` tool.
class WebSearchToolHandler implements ToolHandler {
  WebSearchToolHandler({
    required WebSearcher webSearcher,
  }) : _webSearcher = webSearcher;

  final WebSearcher _webSearcher;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
        description: '搜索外部网页并返回结构化结果列表。',
        parameters: {
          'query': 'string',
          'maxResults': 'int?',
        },
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final query = rawArguments['query'];
    if (query is! String || query.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_query',
        errorSummary: '联网搜索失败：缺少有效查询词',
      );
    }

    final maxResults = rawArguments['maxResults'] ?? rawArguments['num_results'];
    final normalizedMaxResults =
        maxResults is num ? maxResults.toInt().clamp(1, 10) : 5;
    return ToolArgumentResolution.valid({
      'query': query.trim(),
      'maxResults': normalizedMaxResults,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _webSearcher(
      query: context.arguments['query'] as String,
      maxResults: context.arguments['maxResults'] as int?,
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
        contentType: MessageContentType.plainText,
      ),
    ];
  }

  String _buildContextText(ToolResult toolResult) {
    final buffer = StringBuffer()
      ..writeln('以下是工具 `${toolResult.toolName}` 的执行结果，请结合这些信息回答用户。')
      ..writeln('状态：${toolResult.status.name}');

    final payload = toolResult.payload;
    if (payload['query'] is String) {
      buffer.writeln('查询词：${payload['query']}');
    }

    final results = payload['results'];
    if (results is List && results.isNotEmpty) {
      buffer.writeln('联网搜索结果：');
      for (final result in results.take(3)) {
        if (result is! Map) {
          continue;
        }
        final title = (result['title'] ?? '').toString().trim();
        final snippet = _truncateContextText(
          (result['snippet'] ?? '').toString().trim(),
          maxLength: 160,
        );
        final source = (result['source'] ?? '').toString().trim();
        final url = (result['url'] ?? '').toString().trim();
        final titleText = title.isEmpty ? url : title;
        final sourceText = source.isEmpty ? 'unknown' : source;
        buffer.writeln('- [$sourceText] $titleText');
        if (snippet.isNotEmpty) {
          buffer.writeln('  摘要：$snippet');
        }
        if (url.isNotEmpty) {
          buffer.writeln('  链接：$url');
        }
      }
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
