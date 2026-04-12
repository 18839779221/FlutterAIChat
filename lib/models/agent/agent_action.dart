import '../tool/tool_call.dart';

enum AgentActionType {
  respond,
  callTool,
}

class AgentAction {
  final AgentActionType type;
  final String? response;
  final ToolCall? toolCall;

  const AgentAction._({
    required this.type,
    this.response,
    this.toolCall,
  });

  const AgentAction.respond(String response)
      : this._(
          type: AgentActionType.respond,
          response: response,
        );

  const AgentAction.callTool(ToolCall toolCall)
      : this._(
          type: AgentActionType.callTool,
          toolCall: toolCall,
        );
}
