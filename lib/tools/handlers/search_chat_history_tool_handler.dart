import '../../models/chat_message.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Host callback used to search persisted messages for the active chat group.
typedef ChatHistorySearcher = Future<ToolResult> Function({
  required int groupId,
  required String query,
  required int maxResults,
});

/// Handles the complete runtime behavior for the `search_chat_history` tool.
class SearchChatHistoryToolHandler implements ToolHandler {
  SearchChatHistoryToolHandler({
    required ChatHistorySearcher searcher,
  }) : _searcher = searcher;

  final ChatHistorySearcher _searcher;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'search_chat_history',
        title: '搜索聊天记录',
        description: '搜索当前会话里的历史消息，找出和用户问题相关的内容。',
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
        errorSummary: '搜索历史记录失败：缺少有效查询词',
      );
    }

    final maxResults = rawArguments['maxResults'];
    final normalizedMaxResults =
        maxResults is num ? maxResults.toInt().clamp(1, 10) : 3;
    return ToolArgumentResolution.valid({
      'query': query.trim(),
      'maxResults': normalizedMaxResults,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _searcher(
      groupId: context.groupId,
      query: context.arguments['query'] as String,
      maxResults: context.arguments['maxResults'] as int,
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
    if (payload['query'] is String) {
      buffer.writeln('查询词：${payload['query']}');
    }

    final matches = payload['matches'];
    if (matches is List && matches.isNotEmpty) {
      buffer.writeln('命中历史消息：');
      for (final match in matches) {
        if (match is! Map) {
          continue;
        }
        final role = (match['role'] ?? 'unknown').toString();
        final text = (match['text'] ?? '').toString();
        buffer.writeln('- [$role] $text');
      }
    } else if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    return buffer.toString().trim();
  }
}
