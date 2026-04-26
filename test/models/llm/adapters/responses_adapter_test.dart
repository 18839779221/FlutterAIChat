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
    test('serialises input items with input_text/output_text types and store=false',
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
      expect(payload.containsKey('reasoning'), isFalse);
      final input = payload['input'] as List<dynamic>;
      expect(input[0]['content'][0]['type'], 'input_text');
      expect(input[1]['content'][0]['type'], 'output_text');
    });

    test('emits function_call / function_call_output for tool transcript', () {
      final payload = adapter.buildChatPayload(
        messages: [
          ChatMessage(text: '写文件', role: MessageRole.user),
          ChatMessage(
            text: '[tool_use]',
            role: MessageRole.assistant,
            payloadJson: const {
              'modelContextType': 'assistantToolUse',
              'toolName': 'write_file',
              'arguments': {'path': 'a.txt'},
            },
          ),
          ChatMessage(
            text: 'ok',
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
        'type': 'function_call',
        'call_id': 'fc_ctx_1',
        'name': 'write_file',
        'arguments': '{"path":"a.txt"}',
      });
      expect(input[2], {
        'type': 'function_call_output',
        'call_id': 'fc_ctx_1',
        'output': 'ok',
      });
    });
  });

  group('ResponsesAdapter.buildPlannerPayload', () {
    test('forces store=true and injects previous_response_id', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 'd',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
        previousResponseId: 'resp_prev',
      );
      expect(payload['store'], true);
      expect(payload['previous_response_id'], 'resp_prev');
      expect(payload['tool_choice'], 'auto');
      expect((payload['tools'] as List).first, {
        'type': 'function',
        'name': 'search',
        'description': 'd',
        'parameters': {'type': 'object'},
      });
    });

    test(
        'when previousResponseId is set and only user_interaction_answer continuation, input is continuation-only',
        () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        availableTools: const [],
        parallelToolCalls: true,
        previousResponseId: 'resp_prev',
        continuationItems: const [
          {'type': 'user_interaction_answer', 'content': 'A'},
        ],
      );
      final input = payload['input'] as List<dynamic>;
      expect(input.length, 1);
      expect(input[0]['role'], 'user');
      expect(input[0]['content'][0], {'type': 'input_text', 'text': 'A'});
    });

    test('appends continuation items when no previousResponseId', () {
      final payload = adapter.buildPlannerPayload(
        messages: [ChatMessage(text: 'q', role: MessageRole.user)],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-x',
        availableTools: const [],
        parallelToolCalls: true,
        continuationItems: const [
          {
            'type': 'function_call_output',
            'call_id': 'fc_1',
            'output': 'done',
          },
        ],
      );
      final input = payload['input'] as List<dynamic>;
      expect(input.length, 2);
      expect(input.last, {
        'type': 'function_call_output',
        'call_id': 'fc_1',
        'output': 'done',
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
