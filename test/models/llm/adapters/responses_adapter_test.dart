import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = ResponsesAdapter();

  group('ResponsesAdapter.buildHeaders', () {
    test('uses Bearer auth', () {
      final headers = adapter.buildHeaders(
        const LLMConfig(apiKey: 'k1', apiUrl: 'u', model: 'm'),
      );
      expect(headers['Authorization'], 'Bearer k1');
    });
  });

  group('ResponsesAdapter.buildChatPayload', () {
    test(
        'serialises input items with input_text/output_text types and requests reasoning summary',
        () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: 'hi', role: MessageRole.user),
          ChatMessage(text: 'yes', role: MessageRole.assistant),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        stream: true,
      );

      expect(payload['store'], false);
      expect(payload['stream'], true);
      expect(payload['reasoning'], {
        'effort': 'medium',
        'summary': 'auto',
      });
      final input = payload['input'] as List<dynamic>;
      expect(input[0]['content'][0]['type'], 'input_text');
      expect(input[1]['content'][0]['type'], 'output_text');
    });

    test('reuses providerCallId for tool transcript', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '写文件', role: MessageRole.user),
          ChatMessage(
            text: '[tool_use]',
            role: MessageRole.assistant,
            payloadJson: const {
              'modelContextType': 'assistantToolUse',
              'providerCallId': 'fc_server_1',
              'toolName': 'write_file',
              'arguments': {'path': 'a.txt'},
            },
          ),
          ChatMessage(
            text: 'ok',
            role: MessageRole.user,
            payloadJson: const {
              'modelContextType': 'userToolResult',
              'providerCallId': 'fc_server_1',
              'toolName': 'write_file',
            },
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        stream: false,
      );
      final input = payload['input'] as List<dynamic>;
      expect(input[1], {
        'type': 'function_call',
        'call_id': 'fc_server_1',
        'name': 'write_file',
        'arguments': '{"path":"a.txt"}',
      });
      expect(input[2], {
        'type': 'function_call_output',
        'call_id': 'fc_server_1',
        'output': 'ok',
      });
    });

    test('falls back to plain text items when providerCallId is missing', () {
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

      final input = payload['input'] as List<dynamic>;
      expect(input[1], {
        'role': 'assistant',
        'content': [
          {
            'type': 'output_text',
            'text': '[assistant tool_use] write_file path=a.txt',
          },
        ],
      });
      expect(input[2], {
        'role': 'user',
        'content': [
          {
            'type': 'input_text',
            'text': '[user tool_result] ok',
          },
        ],
      });
    });
  });

  group('ResponsesAdapter.parsePlannerChoice', () {
    test('parses function_call from output array', () {
      final choice = adapter.parsePlannerChoice({
        'output': [
          {
            'type': 'function_call',
            'name': 'search',
            'arguments': '{"q":"x"}',
          },
        ],
      });
      expect(choice?.isToolCall, isTrue);
      expect(choice?.toolName, 'search');
      expect(choice?.arguments, {'q': 'x'});
    });

    test('parses message.output_text as response', () {
      final choice = adapter.parsePlannerChoice({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'hi'},
            ],
          },
        ],
      });
      expect(choice?.response, 'hi');
    });

    test('falls back to top-level output_text', () {
      final choice = adapter.parsePlannerChoice({'output_text': '直接回答'});
      expect(choice?.response, '直接回答');
    });

    test('returns null when nothing decodable', () {
      expect(adapter.parsePlannerChoice({}), isNull);
    });
  });

  group('ResponsesAdapter.extractNonStreamText', () {
    test('returns output_text when present', () {
      expect(
        adapter.extractNonStreamText({'output_text': 'x'}),
        'x',
      );
    });

    test('aggregates output[].message.output_text content', () {
      final text = adapter.extractNonStreamText({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'a'},
              {'type': 'output_text', 'text': 'b'},
            ],
          },
        ],
      });
      expect(text, 'ab');
    });
  });
}
