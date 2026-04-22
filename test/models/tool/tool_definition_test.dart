import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/localized_tool_text.dart';
import 'package:ai_chat/services/prompt/prompt_locale.dart';
import 'package:ai_chat/tools/handlers/ask_user_question_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolDefinition', () {
    test('runtime metadata defaults to immediate and is exported to planner', () {
      const definition = ToolDefinition(
        name: 'ask_user_question',
        title: '向用户提问',
        runtimeKind: ToolRuntimeKind.userInteraction,
      );

      expect(definition.runtimeKind, ToolRuntimeKind.userInteraction);
      expect(definition.resolvedRuntimeKind, ToolRuntimeKind.userInteraction);
    });

    test('user interaction tools can advertise structured question schema', () {
      const definition = ToolDefinition(
        name: 'ask_user_question',
        title: '向用户提问',
        descriptionForModel: '当完成任务缺少关键信息时，先向用户提问再继续。',
        runtimeKind: ToolRuntimeKind.userInteraction,
        argumentSchema: ToolArgumentSchema(
          properties: {
            'questions': ToolArgumentProperty(
              type: 'array',
              description: '需要用户回答的问题列表',
            ),
          },
          required: ['questions'],
        ),
      );

      expect(definition.resolvedRuntimeKind, ToolRuntimeKind.userInteraction);
      expect(
        definition.toPlannerJsonSchema()['required'],
        contains('questions'),
      );
    });

    test('导出给 planner 的 json schema 包含 required 字段', () {
      const definition = ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
        descriptionForModel: '当用户需要实时外部信息时使用。',
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

    test('localized title and description resolve correctly', () {
      const definition = ToolDefinition(
        name: 'fetch_webpage',
        title: 'Fetch Webpage',
        localizedTitle:
            LocalizedToolText(english: 'Fetch Webpage', chinese: '读取网页'),
        descriptionForModel: '当用户已经提供 URL，需要直接读取网页内容时使用。',
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

      expect(definition.resolveTitle(PromptLocale.english), 'Fetch Webpage');
      expect(definition.resolveTitle(PromptLocale.chinese), '读取网页');
      expect(
        definition.resolveDescriptionForModel(PromptLocale.english),
        '当用户已经提供 URL，需要直接读取网页内容时使用。',
      );
    });

    test('planner-facing metadata defaults to english and can resolve chinese', () {
      const definition = ToolDefinition(
        name: 'web_search',
        title: 'Web Search',
        localizedTitle: LocalizedToolText(
          english: 'Web Search',
          chinese: '联网搜索',
        ),
        descriptionForModel: 'Use this for real-time web information.',
        localizedDescriptionForModel: LocalizedToolText(
          english: 'Use this for real-time web information.',
          chinese: '当用户需要实时外部信息时使用。',
        ),
        argumentSchema: ToolArgumentSchema(
          properties: {
            'query': ToolArgumentProperty.string(
              description: 'Short search query.',
              localizedDescription: LocalizedToolText(
                english: 'Short search query.',
                chinese: '短而具体的搜索词。',
              ),
            ),
          },
          required: ['query'],
        ),
      );

      expect(definition.resolveTitle(PromptLocale.english), 'Web Search');
      expect(definition.resolveTitle(PromptLocale.chinese), '联网搜索');
      expect(
        definition.resolveDescriptionForModel(PromptLocale.english),
        'Use this for real-time web information.',
      );
      expect(
        definition.resolveDescriptionForModel(PromptLocale.chinese),
        '当用户需要实时外部信息时使用。',
      );
      expect(
        definition.toPlannerJsonSchema(locale: PromptLocale.english),
        {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Short search query.',
            },
          },
          'required': ['query'],
        },
      );
      expect(
        definition.toPlannerJsonSchema(locale: PromptLocale.chinese),
        {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '短而具体的搜索词。',
            },
          },
          'required': ['query'],
        },
      );
    });

    test('ask user question schema exports nested array items for strict providers',
        () {
      final definition = AskUserQuestionToolHandler().definition;
      final schema = definition.toPlannerJsonSchema();
      final questions = (schema['properties'] as Map<String, dynamic>)['questions']
          as Map<String, dynamic>;
      final questionItems = questions['items'] as Map<String, dynamic>;
      final options = (questionItems['properties'] as Map<String, dynamic>)['options']
          as Map<String, dynamic>;

      expect(questions['type'], 'array');
      expect(questionItems['type'], 'object');
      expect(questionItems['required'], containsAll(['id', 'question']));
      expect(options['type'], 'array');
      expect(
        (options['items'] as Map<String, dynamic>)['type'],
        'object',
      );
      expect(
        (options['items'] as Map<String, dynamic>)['required'],
        contains('label'),
      );
    });
  });
}
