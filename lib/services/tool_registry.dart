import '../models/tool/tool_definition.dart';

class ToolRegistry {
  ToolRegistry({List<ToolDefinition>? tools})
      : _tools = tools ??
            const [
              ToolDefinition(
                name: 'search_chat_history',
                description: '搜索当前会话里的历史消息，找出和用户问题相关的内容。',
                parameters: {
                  'query': 'string',
                  'maxResults': 'int?',
                },
              ),
            ];

  final List<ToolDefinition> _tools;

  List<ToolDefinition> getAllTools() => List.unmodifiable(_tools);

  ToolDefinition? findByName(String name) {
    for (final tool in _tools) {
      if (tool.name == name) {
        return tool;
      }
    }
    return null;
  }
}
