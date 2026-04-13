import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/services/planner_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlannerPromptBuilder', () {
    test('会输出工具描述、使用边界和退出规则', () {
      final builder = PlannerPromptBuilder();
      final prompt = builder.buildSystemPrompt(
        visibleTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '需要实时信息时使用。',
            whenToUse: ['用户需要最新资料'],
            whenNotToUse: ['用户已经给出 URL'],
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
        ],
      );

      expect(prompt, contains('什么时候使用'));
      expect(prompt, contains('什么时候不要使用'));
      expect(prompt, contains('需要实时信息时使用。'));
      expect(prompt, contains('如果已有足够信息则直接回答用户'));
    });
  });
}
