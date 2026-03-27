import '../models/chat_message.dart';
import '../models/tool/tool_result.dart';
import '../storage/chat_storage.dart';

export '../models/tool/tool_result.dart';

class ToolExecutor {
  ToolExecutor({required ChatStorage chatStorage}) : _chatStorage = chatStorage;

  final ChatStorage _chatStorage;

  Future<ToolResult> executeSearchChatHistory({
    required int groupId,
    required String query,
    int maxResults = 3,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const ToolResult(
        toolName: 'search_chat_history',
        status: ToolExecutionStatus.failure,
        displayText: '搜索失败：查询内容不能为空',
        payload: {
          'reason': 'empty_query',
        },
      );
    }

    final messages = await _chatStorage.getMessagesByGroup(groupId);
    final matches = messages
        .where((message) => _isSearchableMessage(message, normalizedQuery))
        .take(maxResults)
        .map(_buildMatchPayload)
        .toList();

    return ToolResult(
      toolName: 'search_chat_history',
      status: ToolExecutionStatus.success,
      displayText: '已执行：搜索历史记录',
      payload: {
        'query': normalizedQuery,
        'matchCount': matches.length,
        'matches': matches,
      },
    );
  }

  bool _isSearchableMessage(ChatMessage message, String query) {
    return message.text.trim().isNotEmpty && message.text.contains(query);
  }

  Map<String, dynamic> _buildMatchPayload(ChatMessage message) {
    return {
      'id': message.id,
      'text': _truncatePreview(message.text),
      'role': message.role.name,
      'timestamp': message.timestamp.toIso8601String(),
    };
  }

  String _truncatePreview(String text) {
    final normalized = text.trim();
    if (normalized.length <= 80) {
      return normalized;
    }
    return '${normalized.substring(0, 80)}...';
  }
}
