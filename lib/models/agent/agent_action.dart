import '../tool/tool_call.dart';

enum AgentActionType {
  respond,
  callTool,
}

class AgentAction {
  final AgentActionType type;
  final String? response;
  final ToolCall? toolCall;
  final String? diagnosticCode;

  const AgentAction._({
    required this.type,
    this.response,
    this.toolCall,
    this.diagnosticCode,
  });

  const AgentAction.respond(
    String response, {
    String? diagnosticCode,
  })
      : this._(
          type: AgentActionType.respond,
          response: response,
          diagnosticCode: diagnosticCode,
        );

  const AgentAction.callTool(
    ToolCall toolCall, {
    String? diagnosticCode,
  })
      : this._(
          type: AgentActionType.callTool,
          toolCall: toolCall,
          diagnosticCode: diagnosticCode,
        );
}
