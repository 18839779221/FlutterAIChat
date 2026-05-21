import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/chat_completions_adapter.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = LegacyChatCompletionsAdapter();

  group('LegacyChatCompletionsAdapter.buildHeaders', () {
    test('uses Bearer auth', () {
      final headers = adapter.buildHeaders(
        const LLMConfig(apiKey: 'k1', apiUrl: 'u', model: 'm'),
      );
      expect(headers['Authorization'], 'Bearer k1');
      expect(headers['Content-Type'], 'application/json');
    });
  });

  group('LegacyChatCompletionsAdapter.buildChatPayload', () {
    test('prepends configured system prompt and serialises plain messages', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '你好', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: 'be concise'),
        modelName: 'gpt-x',
        stream: true,
      );

      expect(payload['model'], 'gpt-x');
      expect(payload['stream'], true);
      expect(payload['messages'], [
        {'role': 'system', 'content': 'be concise'},
        {'role': 'user', 'content': '你好'},
      ]);
    });

    test('reuses providerCallId for tool_calls and tool results', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '写文件', role: MessageRole.user),
          ChatMessage(
            text: '[tool_use] write',
            role: MessageRole.assistant,
            payloadJson: const {
              'modelContextType': 'assistantToolUse',
              'providerCallId': 'call_server_1',
              'toolName': 'write_file',
              'arguments': {'path': 'a.txt'},
            },
          ),
          ChatMessage(
            text: 'ok',
            role: MessageRole.user,
            payloadJson: const {
              'modelContextType': 'userToolResult',
              'providerCallId': 'call_server_1',
              'toolName': 'write_file',
            },
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        stream: false,
      );

      final messages = payload['messages'] as List<dynamic>;
      expect(messages[1]['tool_calls'][0]['id'], 'call_server_1');
      expect(messages[1]['tool_calls'][0]['function']['name'], 'write_file');
      expect(messages[1]['tool_calls'][0]['function']['arguments'],
          '{"path":"a.txt"}');
      expect(messages[2], {
        'role': 'tool',
        'tool_call_id': 'call_server_1',
        'content': 'ok',
      });
    });

    test('falls back to plain text when providerCallId is missing', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '写文件', role: MessageRole.user),
          ChatMessage(
            text: '[assistant tool_use] write_file path=a.txt',
            role: MessageRole.assistant,
            payloadJson: const {
              'modelContextType': 'assistantToolUse',
              'toolName': 'write_file',
              'arguments': {'path': 'a.txt'},
            },
          ),
          ChatMessage(
            text: '[user tool_result] ok',
            role: MessageRole.user,
            payloadJson: const {
              'modelContextType': 'userToolResult',
              'toolName': 'write_file',
            },
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        stream: false,
      );

      final messages = payload['messages'] as List<dynamic>;
      expect(messages[1], {
        'role': 'assistant',
        'content': '[assistant tool_use] write_file path=a.txt',
      });
      expect(messages[2], {
        'role': 'user',
        'content': '[user tool_result] ok',
      });
    });
  });

  group('LegacyChatCompletionsAdapter.buildPlannerPayload', () {
    test('emits tool declarations and keeps transcript messages', () {
      final payload = adapter.buildPlannerPayload(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'search the web',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );

      expect(payload['tool_choice'], 'auto');
      expect(payload['parallel_tool_calls'], true);
      expect((payload['tools'] as List).first, {
        'type': 'function',
        'function': {
          'name': 'search',
          'description': 'search the web',
          'parameters': {'type': 'object'},
        },
      });
      final messages = payload['messages'] as List<dynamic>;
      expect(messages.length, 1);
      expect(messages[0], {'role': 'user', 'content': '继续'});
    });

    test('omits tools when none provided', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        availableTools: const [],
        parallelToolCalls: false,
      );
      expect(payload.containsKey('tools'), isFalse);
      expect(payload.containsKey('tool_choice'), isFalse);
    });

    test(
        'omits parallel_tool_calls for deepseek models '
        '(DeepSeek API rejects this field with 400)', () {
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

      expect(payload.containsKey('parallel_tool_calls'), isFalse);
      expect(payload.containsKey('tools'), isTrue);
      expect(payload['tool_choice'], 'auto');
    });

    test('includes parallel_tool_calls for non-deepseek models', () {
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

  group('LegacyChatCompletionsAdapter.parsePlannerChoice', () {
    test('parses assistant tool_calls into PlannerToolChoice.callTool', () {
      final choice = adapter.parsePlannerChoice({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'function': {
                    'name': 'search',
                    'arguments': '{"q":"x"}',
                  },
                },
              ],
            },
          },
        ],
      });
      expect(choice?.isToolCall, isTrue);
      expect(choice?.toolName, 'search');
      expect(choice?.arguments, {'q': 'x'});
    });

    test('falls back to message content when no tool call', () {
      final choice = adapter.parsePlannerChoice({
        'choices': [
          {
            'message': {'content': '<think>先判断是否需要工具</think>\n\nhello'},
          },
        ],
      });
      expect(choice?.isToolCall, isFalse);
      expect(choice?.response, 'hello');
    });

    test('extracts text from array content blocks', () {
      final choice = adapter.parsePlannerChoice({
        'choices': [
          {
            'message': {
              'content': [
                {'type': 'text', 'text': 'alpha'},
                {'type': 'text', 'text': 'beta'},
              ],
            },
          },
        ],
      });
      expect(choice?.response, 'alphabeta');
    });

    test('returns null for empty choices', () {
      expect(adapter.parsePlannerChoice({'choices': []}), isNull);
      expect(adapter.parsePlannerChoice({}), isNull);
    });
  });

  group('LegacyChatCompletionsAdapter.extractNonStreamText', () {
    test('returns the first choice message content', () {
      final text = adapter.extractNonStreamText({
        'choices': [
          {
            'message': {'content': '<think>先分析</think>\n\n结果'},
          },
        ],
      });
      expect(text, '结果');
    });
  });
}
