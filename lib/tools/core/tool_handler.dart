import '../../models/chat_message.dart';
import '../../models/tool/tool_definition.dart';
import '../../models/tool/tool_result.dart';
import 'tool_argument_resolution.dart';
import 'tool_execution_context.dart';

/// Defines the contract each tool runtime component must implement.
abstract class ToolHandler {
  /// Static metadata advertised to the tool decision layer.
  ToolDefinition get definition;

  /// Validates and normalizes raw arguments emitted by the model.
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  });

  /// Executes the tool using normalized input.
  Future<ToolResult> execute(ToolExecutionContext context);

  /// Builds optional planner-visible follow-up context from the tool result.
  /// Most tools can rely on the empty default and let transcript replay carry
  /// the result semantics forward.
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }
}
