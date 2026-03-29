import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_call.dart';
import 'tool_registry.dart';

class ToolDecisionService {
  ToolDecisionService({
    required BaseLLM llm,
    ToolRegistry? toolRegistry,
  })  : _llm = llm,
        _toolRegistry = toolRegistry ?? ToolRegistry();

  final BaseLLM _llm;
  final ToolRegistry _toolRegistry;

  Future<ToolCall?> decideTool({
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
      return null;
    }

    final toolDefinition = _toolRegistry.findByName(toolCall.toolName);
    if (toolDefinition == null) {
      return null;
    }

    return toolCall;
  }

  ToolCall? _tryParseToolCall(String rawDecision) {
    try {
      return ToolCall.fromRawJson(rawDecision);
    } catch (_) {
      return null;
    }
  }
}
