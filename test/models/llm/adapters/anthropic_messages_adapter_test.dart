import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = AnthropicMessagesAdapter();

  group('AnthropicMessagesAdapter.buildHeaders', () {
    test('uses x-api-key and anthropic-version', () {
      final headers = adapter.buildHeaders(
        const LLMConfig(apiKey: 'k1', apiUrl: 'u', model: 'm'),
      );
      expect(headers['x-api-key'], 'k1');
      expect(headers['anthropic-version'], '2023-06-01');
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('AnthropicMessagesAdapter.buildChatPayload', () {
    test('moves configured and embedded system prompts into system field', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: 'ignored-inline', role: MessageRole.system),
          ChatMessage(text: '你好', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: 'top'),
        modelName: 'claude',
        stream: true,
      );

      expect(payload['system'], 'top\n\nignored-inline');
      expect(payload['max_tokens'], 4096);
      final messages = payload['messages'] as List<dynamic>;
      expect(messages.length, 1);
      expect(messages[0]['role'], 'user');
      expect(messages[0]['content'][0]['text'], '你好');
    });

    test('omits system field when no prompt is configured', () {
      final payload = adapter.buildChatPayload(
        messages: [ChatMessage(text: 'hi', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude',
        stream: false,
      );
      expect(payload.containsKey('system'), isFalse);
    });

    test('reuses providerCallId for historical transcript', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '写', role: MessageRole.user),
          ChatMessage(
            text: '[tool_use]',
            role: MessageRole.assistant,
            payloadJson: const {
              'modelContextType': 'assistantToolUse',
              'providerCallId': 'toolu_server_1',
              'toolName': 'write_file',
              'arguments': {'path': 'a.txt'},
            },
          ),
          ChatMessage(
            text: 'ok',
            role: MessageRole.user,
            payloadJson: const {
              'modelContextType': 'userToolResult',
              'providerCallId': 'toolu_server_1',
              'toolName': 'write_file',
            },
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude',
        stream: false,
      );
      final messages = payload['messages'] as List<dynamic>;
      expect(messages[1], {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_server_1',
            'name': 'write_file',
            'input': {'path': 'a.txt'},
          },
        ],
      });
      expect(messages[2], {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_server_1',
            'content': 'ok',
          },
        ],
      });
    });

    test('falls back to text blocks when providerCallId is missing', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '写', role: MessageRole.user),
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
        modelName: 'claude',
        stream: false,
      );

      final messages = payload['messages'] as List<dynamic>;
      expect(messages[1], {
        'role': 'assistant',
        'content': [
          {
            'type': 'text',
            'text': '[assistant tool_use] write_file path=a.txt',
          },
        ],
      });
      expect(messages[2], {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': '[user tool_result] ok',
          },
        ],
      });
    });
  });

  group('AnthropicMessagesAdapter.buildPlannerPayload', () {
    test('emits anthropic-style tools and tool_choice', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'd',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );
      expect(payload['tool_choice'], {'type': 'auto'});
      expect((payload['tools'] as List).first, {
        'name': 'search',
        'description': 'd',
        'input_schema': {'type': 'object'},
      });
    });

    test(
        'prepends assistant content_blocks from providerState when continuation lacks assistant turn',
        () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude',
        availableTools: const [],
        parallelToolCalls: true,
        providerState: const {
          'content_blocks': [
            {'type': 'thinking', 'thinking': 'reasoning'},
            {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'search',
              'input': {'q': 'x'},
            },
          ],
        },
        continuationItems: const [
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_1',
                'content': 'done',
              },
            ],
          },
        ],
      );
      final messages = payload['messages'] as List<dynamic>;
      expect(messages.length, 3);
      expect(messages[1]['role'], 'assistant');
      expect((messages[1]['content'] as List).length, 2);
      expect(messages[2]['content'][0]['type'], 'tool_result');
    });

    test(
        'does not prepend content_blocks when continuation already has assistant turn',
        () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude',
        availableTools: const [],
        parallelToolCalls: true,
        providerState: const {
          'content_blocks': [
            {'type': 'text', 'text': 'stale'},
          ],
        },
        continuationItems: const [
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'fresh'},
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'x', 'content': 'y'},
            ],
          },
        ],
      );
      final messages = payload['messages'] as List<dynamic>;
      expect(messages.length, 3);
      expect(messages[1]['content'][0]['text'], 'fresh');
    });
  });

  group('AnthropicMessagesAdapter.parsePlannerChoice', () {
    test('parses tool_use block into callTool', () {
      final choice = adapter.parsePlannerChoice({
        'content': [
          {
            'type': 'tool_use',
            'name': 'search',
            'input': {'q': 'x'},
          },
        ],
      });
      expect(choice?.isToolCall, isTrue);
      expect(choice?.toolName, 'search');
      expect(choice?.arguments, {'q': 'x'});
    });

    test('returns text block as response', () {
      final choice = adapter.parsePlannerChoice({
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
      });
      expect(choice?.response, 'hello');
    });

    test('returns thinking block as response', () {
      final choice = adapter.parsePlannerChoice({
        'content': [
          {'type': 'thinking', 'thinking': 'reasoning'},
        ],
      });
      expect(choice?.response, 'reasoning');
    });

    test('returns null when content missing', () {
      expect(adapter.parsePlannerChoice({}), isNull);
    });
  });

  group('AnthropicMessagesAdapter.extractNonStreamText', () {
    test('concatenates text/thinking blocks', () {
      final text = adapter.extractNonStreamText({
        'content': [
          {'type': 'thinking', 'thinking': 'r'},
          {'type': 'text', 'text': 'a'},
          {'type': 'text', 'text': 'b'},
          {'type': 'tool_use', 'name': 'x'},
        ],
      });
      expect(text, 'rab');
    });

    test('returns empty string when content is not a list', () {
      expect(adapter.extractNonStreamText({'content': 'oops'}), '');
    });
  });
}
