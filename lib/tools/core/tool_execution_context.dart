import '../../models/chat_event.dart';
import '../../models/chat_message.dart';
import '../../models/workspace/resolved_workspace.dart';
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

  /// Append-only events already recorded for the current turn.
  ///
  /// Tool handlers use these execution facts for runtime guards such as
  /// duplicate skill invocation checks. This is not the UI timeline.
  final List<ChatEvent> currentTurnEvents;

  /// Stable execution timestamp used by handlers that normalize relative time.
  final DateTime now;

  /// Host adapter bundle used to call platform or infrastructure capabilities.
  final ToolHostAdapters hostAdapters;

  /// Effective current working directory for relative file paths in this tool execution.
  final String cwd;

  /// Resolved workspace for the active group when available.
  final ResolvedWorkspace? workspace;

  ToolExecutionContext({
    required this.groupId,
    required this.toolName,
    required Map<String, dynamic> arguments,
    required List<ChatMessage> history,
    List<ChatEvent> currentTurnEvents = const <ChatEvent>[],
    required this.now,
    this.hostAdapters = const ToolHostAdapters(),
    this.cwd = '/',
    this.workspace,
  })  : arguments = Map<String, dynamic>.unmodifiable(arguments),
        history = List<ChatMessage>.unmodifiable(history),
        currentTurnEvents = List<ChatEvent>.unmodifiable(currentTurnEvents);
}
