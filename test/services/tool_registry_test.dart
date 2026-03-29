import 'package:ai_chat/services/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolRegistry', () {
    test('默认暴露第一批 6 个工具', () {
      final registry = ToolRegistry();

      expect(registry.getAllTools(), hasLength(6));
      expect(
        registry.getAllTools().map((tool) => tool.name),
        containsAll(const [
          'search_chat_history',
          'fetch_webpage',
          'save_note',
          'create_reminder',
          'create_calendar_event',
          'share_result',
        ]),
      );
    });

    test('search_chat_history 工具提供稳定元数据', () {
      final registry = ToolRegistry();

      final tool = registry.findByName('search_chat_history');

      expect(tool, isNotNull);
      expect(tool!.description, contains('历史'));
      expect(tool.title, '搜索聊天记录');
      expect(tool.parameters, containsPair('query', 'string'));
      expect(tool.parameters, containsPair('maxResults', 'int?'));
      expect(tool.requiresConfirmation, isFalse);
    });

    test('未注册工具返回空结果', () {
      final registry = ToolRegistry();

      expect(registry.findByName('missing_tool'), isNull);
    });
  });
}
