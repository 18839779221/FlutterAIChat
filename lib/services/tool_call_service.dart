import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_call.dart';
import '../models/tool/tool_definition.dart';
import 'tool_executor.dart';
import 'tool_registry.dart';

class ToolPreparationResult {
  final ToolResult? toolResult;
  final List<ChatMessage> additionalContextMessages;

  const ToolPreparationResult({
    required this.toolResult,
    required this.additionalContextMessages,
  });

  const ToolPreparationResult.noTool()
      : toolResult = null,
        additionalContextMessages = const [];
}

class ToolCallService {
  ToolCallService({
    required BaseLLM llm,
    ToolRegistry? toolRegistry,
    required ToolExecutor toolExecutor,
  })  : _llm = llm,
        _toolRegistry = toolRegistry ?? ToolRegistry(),
        _toolExecutor = toolExecutor;

  final BaseLLM _llm;
  final ToolRegistry _toolRegistry;
  final ToolExecutor _toolExecutor;

  Future<ToolPreparationResult> prepareToolContext({
    required int groupId,
    required String userMessage,
    required List<ChatMessage> history,
  }) async {
    final tools = _toolRegistry.getAllTools();
    final rawDecision = await _llm.decideToolCall(
      userMessage: userMessage,
      history: history,
      tools: tools,
    );

    final toolCall = _tryParseToolCall(rawDecision);
    if (toolCall == null || toolCall.toolName == 'none') {
      return const ToolPreparationResult.noTool();
    }

    final toolDefinition = _toolRegistry.findByName(toolCall.toolName);
    if (toolDefinition == null) {
      return const ToolPreparationResult.noTool();
    }

    final toolResult = await _executeTool(
      toolDefinition: toolDefinition,
      toolCall: toolCall,
      groupId: groupId,
    );

    return ToolPreparationResult(
      toolResult: toolResult,
      additionalContextMessages: [
        ChatMessage(
          text: _buildContextText(toolResult),
          role: MessageRole.system,
          status: MessageStatus.completed,
        ),
      ],
    );
  }

  ToolCall? _tryParseToolCall(String rawDecision) {
    try {
      return ToolCall.fromRawJson(rawDecision);
    } catch (_) {
      return null;
    }
  }

  Future<ToolResult> _executeTool({
    required ToolDefinition toolDefinition,
    required ToolCall toolCall,
    required int groupId,
  }) async {
    switch (toolDefinition.name) {
      case 'search_chat_history':
        final query = toolCall.arguments['query'];
        final maxResults = toolCall.arguments['maxResults'];
        if (query is! String || query.trim().isEmpty) {
          return const ToolResult(
            toolName: 'search_chat_history',
            status: ToolExecutionStatus.failure,
            displayText: '搜索历史记录失败',
            payload: {'reason': 'invalid_arguments'},
          );
        }
        return _toolExecutor.executeSearchChatHistory(
          groupId: groupId,
          query: query,
          maxResults: maxResults is num ? maxResults.toInt() : 3,
        );
      default:
        return const ToolResult(
          toolName: 'unknown',
          status: ToolExecutionStatus.failure,
          displayText: '工具执行失败',
          payload: {'reason': 'unsupported_tool'},
        );
    }
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
        if (match is Map) {
          final role = match['role'] ?? 'unknown';
          final text = match['text'] ?? '';
          buffer.writeln('- [$role] $text');
        }
      }
    } else {
      buffer.writeln('未找到相关历史消息。');
    }

    return buffer.toString().trim();
  }
}
