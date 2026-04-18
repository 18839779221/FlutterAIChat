/// Structured planner output that either responds directly or calls a tool.
class PlannerToolChoice {
  /// Final response text when the planner chooses not to call a tool.
  final String? response;

  /// Tool name when the planner selects a tool call.
  final String? toolName;

  /// Tool arguments when the planner selects a tool call.
  final Map<String, dynamic>? arguments;

  const PlannerToolChoice._({
    this.response,
    this.toolName,
    this.arguments,
  });

  const PlannerToolChoice.respond(String response)
      : this._(
          response: response,
        );

  const PlannerToolChoice.callTool({
    required String toolName,
    required Map<String, dynamic> arguments,
  }) : this._(
          toolName: toolName,
          arguments: arguments,
        );

  bool get isRespond =>
      response != null && response!.trim().isNotEmpty && toolName == null;

  bool get isToolCall =>
      toolName != null && toolName!.trim().isNotEmpty && arguments != null;
}
