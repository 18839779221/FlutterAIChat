import '../models/tool/tool_definition.dart';

class ToolRegistry {
  ToolRegistry({List<ToolDefinition>? tools})
      : _tools = tools ??
            const [
              ToolDefinition(
                name: 'search_chat_history',
                title: '搜索聊天记录',
                description: '搜索当前会话里的历史消息，找出和用户问题相关的内容。',
                parameters: {
                  'query': 'string',
                  'maxResults': 'int?',
                },
              ),
              ToolDefinition(
                name: 'fetch_webpage',
                title: '读取网页',
                description: '读取网页正文并返回可供总结的文本内容。',
                parameters: {
                  'url': 'string',
                  'extractMode': 'string?',
                },
              ),
              ToolDefinition(
                name: 'save_note',
                title: '保存笔记',
                description: '将当前内容保存为本地笔记。',
                parameters: {
                  'title': 'string',
                  'content': 'string',
                  'folder': 'string?',
                },
                requiresConfirmation: true,
                riskLevel: 'medium',
              ),
              ToolDefinition(
                name: 'create_reminder',
                title: '创建提醒',
                description: '创建系统提醒事项。',
                parameters: {
                  'title': 'string',
                  'dueAt': 'string?',
                  'note': 'string?',
                },
                requiresConfirmation: true,
                riskLevel: 'medium',
              ),
              ToolDefinition(
                name: 'create_calendar_event',
                title: '创建日历事件',
                description: '创建系统日历事件。',
                parameters: {
                  'title': 'string',
                  'startAt': 'string',
                  'endAt': 'string?',
                  'location': 'string?',
                  'notes': 'string?',
                },
                requiresConfirmation: true,
                riskLevel: 'high',
              ),
              ToolDefinition(
                name: 'share_result',
                title: '分享结果',
                description: '调用系统分享面板分享文本结果。',
                parameters: {
                  'text': 'string',
                  'subject': 'string?',
                },
                requiresConfirmation: true,
                riskLevel: 'high',
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
