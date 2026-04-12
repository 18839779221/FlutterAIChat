import '../../models/tool/tool_definition.dart';
import 'tool_handler.dart';

/// Registers tool handlers and exposes lookup helpers for the runtime.
class ToolRuntimeRegistry {
  ToolRuntimeRegistry({
    required List<ToolHandler> handlers,
  }) : _handlersByName = {
         for (final handler in handlers) handler.definition.name: handler,
       };

  final Map<String, ToolHandler> _handlersByName;

  /// Returns the registered handler for the provided tool name.
  ToolHandler? findHandler(String toolName) {
    return _handlersByName[toolName];
  }

  /// Returns all tool definitions that should be exposed to the decision layer.
  List<ToolDefinition> getAllDefinitions() {
    return _handlersByName.values
        .map((handler) => handler.definition)
        .toList(growable: false);
  }
}
