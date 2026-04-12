import '../../models/chat_message.dart';
import '../adapters/tool_host_adapters.dart';

/// Provides normalized runtime input required by a tool handler execution.
class ToolExecutionContext {
  /// The active chat group identifier for tools that need scoped persistence.
  final int groupId;

  /// Tool name resolved by the runtime registry.
  final String toolName;

  /// Normalized arguments produced by the handler before execution.
  final Map<String, dynamic> arguments;

  /// Conversation history available to the tool when needed.
  final List<ChatMessage> history;

  /// Stable execution timestamp used by handlers that normalize relative time.
  final DateTime now;

  /// Host adapter bundle used to call platform or infrastructure capabilities.
  final ToolHostAdapters hostAdapters;

  ToolExecutionContext({
    required this.groupId,
    required this.toolName,
    required Map<String, dynamic> arguments,
    required List<ChatMessage> history,
    required this.now,
    this.hostAdapters = const ToolHostAdapters(),
  })  : arguments = Map<String, dynamic>.unmodifiable(arguments),
        history = List<ChatMessage>.unmodifiable(history);
}
