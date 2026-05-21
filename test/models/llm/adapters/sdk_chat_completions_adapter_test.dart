import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:ai_chat/models/llm/adapters/sdk_message_converter.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkMessageConverter', () {
    const converter = SdkMessageConverter();

    test('converts system message', () {
      final messages = converter.convert([
        ChatMessage(text: 'You are helpful', role: MessageRole.system),
      ]);
      expect(messages.length, 1);
      final json = messages.first.toJson();
      expect(json['role'], 'system');
      expect(json['content'], 'You are helpful');
    });

    test('converts user message', () {
      final messages = converter.convert([
        ChatMessage(text: 'Hello', role: MessageRole.user),
      ]);
      expect(messages.length, 1);
      final json = messages.first.toJson();
      expect(json['role'], 'user');
      expect(json['content'], 'Hello');
    });

    test('converts plain assistant message', () {
      final messages = converter.convert([
        ChatMessage(text: 'Hi there', role: MessageRole.assistant),
      ]);
      expect(messages.length, 1);
      final json = messages.first.toJson();
      expect(json['role'], 'assistant');
      expect(json['content'], 'Hi there');
      expect(json.containsKey('tool_calls'), isFalse);
    });

    test('converts assistantToolUse with providerCallId', () {
      final messages = converter.convert([
        ChatMessage(
          text: 'Searching...',
          role: MessageRole.assistant,
          payloadJson: {
            'modelContextType': 'assistantToolUse',
            'toolName': 'web_search',
            'providerCallId': 'call_123',
            'arguments': {'query': 'test'},
          },
        ),
      ]);
      expect(messages.length, 1);
      final json = messages.first.toJson();
      expect(json['role'], 'assistant');
      expect(json['tool_calls'], isA<List>());
      expect(json['tool_calls'].first['id'], 'call_123');
      expect(json['tool_calls'].first['function']['name'], 'web_search');
    });

    test('converts userToolResult with toolCallId', () {
      final messages = converter.convert([
        ChatMessage(
          text: 'Search results here',
          role: MessageRole.user,
          payloadJson: {
            'modelContextType': 'userToolResult',
            'toolName': 'web_search',
            'providerCallId': 'call_123',
          },
        ),
      ]);
      expect(messages.length, 1);
      final json = messages.first.toJson();
      expect(json['role'], 'tool');
      expect(json['tool_call_id'], 'call_123');
      expect(json['content'], 'Search results here');
    });

    test('merges adjacent assistant text + toolUse into single message', () {
      final messages = converter.convert([
        ChatMessage(text: 'Let me search', role: MessageRole.assistant),
        ChatMessage(
          text: 'Searching...',
          role: MessageRole.assistant,
          payloadJson: {
            'modelContextType': 'assistantToolUse',
            'toolName': 'web_search',
            'providerCallId': 'call_456',
            'arguments': {'query': 'hello'},
          },
        ),
        ChatMessage(
          text: 'Results here',
          role: MessageRole.user,
          payloadJson: {
            'modelContextType': 'userToolResult',
            'toolName': 'web_search',
            'providerCallId': 'call_456',
          },
        ),
      ]);

      // Should be: assistant(content + toolCalls), tool
      expect(messages.length, 2);

      final assistantJson = messages[0].toJson();
      expect(assistantJson['role'], 'assistant');
      expect(assistantJson['content'], 'Let me search');
      expect(assistantJson['tool_calls'], isA<List>());
      expect(assistantJson['tool_calls'].first['id'], 'call_456');
      expect(assistantJson['tool_calls'].first['function']['name'], 'web_search');

      final toolJson = messages[1].toJson();
      expect(toolJson['role'], 'tool');
      expect(toolJson['tool_call_id'], 'call_456');
    });

    test('does not merge assistant text with non-adjacent toolUse', () {
      final messages = converter.convert([
        ChatMessage(text: 'First response', role: MessageRole.assistant),
        ChatMessage(text: 'User reply', role: MessageRole.user),
        ChatMessage(
          text: 'Calling tool',
          role: MessageRole.assistant,
          payloadJson: {
            'modelContextType': 'assistantToolUse',
            'toolName': 'search',
            'providerCallId': 'call_789',
            'arguments': {},
          },
        ),
      ]);

      // Not merged: assistant(text), user(text), assistant(toolCalls)
      expect(messages.length, 3);
      expect(messages[0].toJson()['content'], 'First response');
      expect(messages[0].toJson().containsKey('tool_calls'), isFalse);
      expect(messages[1].toJson()['role'], 'user');
      expect(messages[2].toJson()['tool_calls'], isA<List>());
    });

    test('filters empty messages', () {
      final messages = converter.convert([
        ChatMessage(text: '', role: MessageRole.assistant),
        ChatMessage(text: '  ', role: MessageRole.user),
        ChatMessage(text: 'Hello', role: MessageRole.user),
      ]);
      expect(messages.length, 1);
      expect(messages.first.toJson()['content'], 'Hello');
    });

    test('toolUse without providerCallId falls back to plain assistant', () {
      final messages = converter.convert([
        ChatMessage(
          text: 'Tool call',
          role: MessageRole.assistant,
          payloadJson: {
            'modelContextType': 'assistantToolUse',
            'toolName': 'search',
            // No providerCallId
          },
        ),
      ]);
      expect(messages.length, 1);
      final json = messages.first.toJson();
      expect(json['role'], 'assistant');
      expect(json['content'], 'Tool call');
      expect(json.containsKey('tool_calls'), isFalse);
    });
  });

  group('SdkChatCompletionsAdapter.buildPlannerPayload', () {
    late SdkChatCompletionsAdapter adapter;

    setUp(() {
      adapter = SdkChatCompletionsAdapter();
    });

    test('includes model, messages, and tools', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'Hello', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'deepseek-chat',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'Search the web',
            inputSchema: {'type': 'object', 'properties': {}},
          ),
        ],
        parallelToolCalls: true,
      );

      expect(payload['model'], 'deepseek-chat');
      expect(payload['messages'], isA<List>());
      expect(payload['tools'], isA<List>());
      expect(payload['tool_choice'], 'auto');
      // parallel_tool_calls should be present for non-DeepSeek model names
      // (the SDK includes it when explicitly set)
    });

    test('merges assistant text + toolUse in planner messages', () {
      final payload = adapter.buildPlannerPayload(
        messages: [
          ChatMessage(text: 'User asks', role: MessageRole.user),
          ChatMessage(text: 'Let me search', role: MessageRole.assistant),
          ChatMessage(
            text: 'Searching...',
            role: MessageRole.assistant,
            payloadJson: {
              'modelContextType': 'assistantToolUse',
              'toolName': 'search',
              'providerCallId': 'call_1',
              'arguments': {'q': 'test'},
            },
          ),
          ChatMessage(
            text: 'Results',
            role: MessageRole.user,
            payloadJson: {
              'modelContextType': 'userToolResult',
              'toolName': 'search',
              'providerCallId': 'call_1',
            },
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'deepseek-chat',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'Search',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );

      final msgs = payload['messages'] as List;
      // Find the assistant message with tool_calls
      final assistantWithTools = msgs.where(
        (m) => m['role'] == 'assistant' && m.containsKey('tool_calls'),
      );
      expect(assistantWithTools.length, 1);

      final assistantMsg = assistantWithTools.first;
      expect(assistantMsg['content'], 'Let me search');
      expect(assistantMsg['tool_calls'], isA<List>());
      expect(assistantMsg['tool_calls'].first['id'], 'call_1');

      // Tool message should follow
      final toolMsgs = msgs.where((m) => m['role'] == 'tool');
      expect(toolMsgs.length, 1);
      expect(toolMsgs.first['tool_call_id'], 'call_1');
    });

    test('does not include parallel_tool_calls for deepseek model', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'hi', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'deepseek-chat',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'search',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );

      // deepseek model should NOT include parallel_tool_calls
      expect(payload.containsKey('parallel_tool_calls'), isFalse);
      expect(payload.containsKey('tools'), isTrue);
      expect(payload['tool_choice'], 'auto');
    });

    test('includes parallel_tool_calls for non-deepseek model', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'hi', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-4o',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'search',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );

      expect(payload['parallel_tool_calls'], true);
    });
  });

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
}
