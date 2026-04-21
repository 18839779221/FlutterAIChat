/// Resolves stable user-facing labels for built-in tool names.
String resolveToolDisplayName(String toolName) {
  switch (toolName.trim()) {
    case 'search_chat_history':
      return '搜索聊天记录';
    case 'web_search':
      return '联网搜索';
    case 'fetch_webpage':
      return '读取网页';
    case 'LS':
      return '列出目录';
    case 'Glob':
      return '查找文件';
    case 'Grep':
      return '搜索文件内容';
    case 'Read':
      return '读取文件';
    case 'Write':
      return '写入文件';
    case 'Edit':
      return '编辑文件';
    case 'create_reminder':
      return '创建提醒';
    case 'create_calendar_event':
      return '创建日历事件';
    case 'share_result':
      return '分享结果';
    default:
      return toolName.trim();
  }
}
