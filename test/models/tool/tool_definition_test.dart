import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolDefinition', () {
    test('导出给 planner 的 json schema 包含 required 字段', () {
      const definition = ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
        description: '搜索外部网页',
        descriptionForModel: '当用户需要实时外部信息时使用。',
        category: ToolCategory.retrieval,
        argumentSchema: ToolArgumentSchema(
          properties: {
            'query': ToolArgumentProperty.string(
              description: '短而具体的搜索词',
            ),
          },
          required: ['query'],
        ),
      );

      expect(definition.toPlannerJsonSchema(), {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '短而具体的搜索词',
          },
        },
        'required': ['query'],
      });
    });

    test('导出给 planner 的 descriptor 包含模型侧描述和使用边界', () {
      const definition = ToolDefinition(
        name: 'fetch_webpage',
        title: '读取网页',
        description: '读取网页正文',
        descriptionForModel: '当用户已经提供 URL，需要直接读取网页内容时使用。',
        category: ToolCategory.retrieval,
        capabilities: [ToolCapability.webUrlReader],
        whenToUse: ['用户消息里已经有 URL'],
        whenNotToUse: ['用户只是想联网搜索但没有给 URL'],
        argumentSchema: ToolArgumentSchema(
          properties: {
            'url': ToolArgumentProperty.string(
              description: '要读取的网页链接',
              format: 'uri',
            ),
          },
          required: ['url'],
        ),
      );

      expect(
        definition.toPlannerDescriptor(),
        containsPair('name', 'fetch_webpage'),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('title', '读取网页'),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('category', 'retrieval'),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('description', '当用户已经提供 URL，需要直接读取网页内容时使用。'),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('whenToUse', ['用户消息里已经有 URL']),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('whenNotToUse', ['用户只是想联网搜索但没有给 URL']),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('capabilities', ['webUrlReader']),
      );
      expect(
        definition.toPlannerDescriptor(),
        containsPair('inputSchema', {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': '要读取的网页链接',
              'format': 'uri',
            },
          },
          'required': ['url'],
        }),
      );
    });
  });
}
