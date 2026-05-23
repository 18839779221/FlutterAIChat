import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkChatCompletionsAdapter.parsePlannerChoice', () {
    late SdkChatCompletionsAdapter adapter;

    setUp(() {
      adapter = SdkChatCompletionsAdapter();
    });

    test('parses text-only response', () {
      final choice = adapter.parsePlannerChoice({
        'object': 'chat.completion',
        'model': 'deepseek-chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Hello there',
            },
            'finish_reason': 'stop',
          },
        ],
      });

      expect(choice, isNotNull);
      expect(choice!.isRespond, isTrue);
      expect(choice.response, 'Hello there');
    });

    test('parses tool call response', () {
      final choice = adapter.parsePlannerChoice({
        'object': 'chat.completion',
        'model': 'deepseek-chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_abc',
                  'type': 'function',
                  'function': {
                    'name': 'web_search',
                    'arguments': '{"query":"test"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });

      expect(choice, isNotNull);
      expect(choice!.isToolCall, isTrue);
      expect(choice.toolName, 'web_search');
      expect(choice.arguments, {'query': 'test'});
    });

    test('parses response with reasoning_content (DeepSeek)', () {
      // Use parseDecision for full ModelTurnDecision
      final decision = adapter.parseDecision({
        'id': 'chatcmpl-123',
        'object': 'chat.completion',
        'model': 'deepseek-chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'The answer is 42',
              'reasoning_content': 'Let me think step by step...',
            },
            'finish_reason': 'stop',
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.assistantMessage, 'The answer is 42');
      expect(decision.visibleReasoning, 'Let me think step by step...');
      expect(decision.toolCalls, isEmpty);
      expect(decision.isTerminal, isTrue);
    });

    test('parses tool call decision', () {
      final decision = adapter.parseDecision({
        'id': 'chatcmpl-456',
        'object': 'chat.completion',
        'model': 'deepseek-chat',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'I will search',
              'tool_calls': [
                {
                  'id': 'call_xyz',
                  'type': 'function',
                  'function': {
                    'name': 'web_search',
                    'arguments': '{"query":"deepseek"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.toolCalls.length, 1);
      expect(decision.toolCalls.first.providerCallId, 'call_xyz');
      expect(decision.toolCalls.first.toolName, 'web_search');
      expect(decision.toolCalls.first.arguments, {'query': 'deepseek'});
      expect(decision.assistantMessage, 'I will search');
      expect(decision.isTerminal, isFalse);
    });
  });

  group('SdkChatCompletionsAdapter.buildPlannerPayloadFromCarriers', () {
    late SdkChatCompletionsAdapter adapter;

    setUp(() {
      adapter = SdkChatCompletionsAdapter();
    });

    test(
        'keeps assistant tool_calls paired with following tool result messages for chat completions continuation',
        () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: [
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
            rawJson: const {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_server_1',
                  'type': 'function',
                  'function': {
                    'name': 'ask_user_question',
                    'arguments': '{"questions":[{"id":"platform"}]}',
                  },
                },
              ],
            },
          ),
          const SyntheticCarrier.toolResult(
            toolCallId: 'call_server_1',
            content: 'User answered AskUserQuestion:\n- platform: Android',
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'deepseek-chat',
        availableTools: const <PlannerToolOption>[],
        parallelToolCalls: false,
      );

      final messages = payload['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'assistant');
      expect(messages[0]['tool_calls'][0]['id'], 'call_server_1');
      expect(messages[1], {
        'role': 'tool',
        'tool_call_id': 'call_server_1',
        'content': 'User answered AskUserQuestion:\n- platform: Android',
      });
    });
  });
}
