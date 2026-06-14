import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/adapters/sdk_responses_adapter.dart';
import 'package:ai_chat/models/llm/llm_request_options.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes max_output_tokens into responses payload', () {
    const adapter = SdkResponsesAdapter();
    final payload = adapter.buildChatPayload(
      messages: [ChatMessage(text: '继续', role: MessageRole.user)],
      config: ChatConfig(systemPrompt: ''),
      modelName: 'gpt-5',
      stream: false,
      requestOptions: const LlmRequestOptions(maxOutputTokens: 4096),
    );

    expect(payload['max_output_tokens'], 4096);
  });

  test('responses planner replay skips reasoning items from raw assistant output',
      () {
    const adapter = SdkResponsesAdapter();
    const raw = {
      'output': [
        {
          'type': 'reasoning',
          'id': 'rs_1',
          'summary': [
            {'type': 'summary_text', 'text': '先思考一下'},
          ],
        },
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'Let me search'},
          ],
        },
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'search',
          'arguments': '{"q":"x"}',
        },
      ],
    };

    final payload = adapter.buildPlannerPayloadFromCarriers(
      carriers: const [
        SyntheticCarrier.system('agent'),
        SyntheticCarrier.user('please'),
        RawAssistantCarrier(
          apiStyle: ChatTurnProviderStyle.openaiResponses,
          rawJson: raw,
        ),
        SyntheticCarrier.toolResult(toolCallId: 'call_1', content: 'OK'),
      ],
      config: ChatConfig(systemPrompt: ''),
      modelName: 'gpt-5',
      availableTools: const [
        PlannerToolOption(
          name: 'search',
          description: 'web search',
          inputSchema: {'type': 'object'},
        ),
      ],
      parallelToolCalls: false,
    );

    final input = (payload['input'] as List).cast<Map<String, dynamic>>();
    expect(input.any((item) => item['type'] == 'reasoning'), isFalse);
    expect(input.any((item) => item['type'] == 'message'), isTrue);
    expect(input.any((item) => item['type'] == 'function_call'), isTrue);
    expect(
      input.any((item) => item['type'] == 'function_call_output'),
      isTrue,
    );
  });
}
