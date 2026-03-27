import 'package:ai_chat/services/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolRegistry', () {
    test('默认只暴露 search_chat_history 工具', () {
      final registry = ToolRegistry();

      expect(registry.getAllTools(), hasLength(1));
      expect(registry.getAllTools().single.name, 'search_chat_history');
    });

    test('search_chat_history 工具提供稳定元数据', () {
      final registry = ToolRegistry();

      final tool = registry.findByName('search_chat_history');

      expect(tool, isNotNull);
      expect(tool!.description, contains('历史'));
      expect(tool.parameters, containsPair('query', 'string'));
      expect(tool.parameters, containsPair('maxResults', 'int?'));
    });

    test('未注册工具返回空结果', () {
      final registry = ToolRegistry();

      expect(registry.findByName('missing_tool'), isNull);
    });
  });
}
