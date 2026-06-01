import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResponsesAdapter.extractRawAssistantMessage', () {
    const adapter = ResponsesAdapter();

    test('保留 output 数组完整（reasoning + message + function_call）', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'resp_1',
        'output': [
          {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
          {
            'type': 'message',
            'id': 'msg_1',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'Let me search'},
            ],
          },
          {
            'type': 'function_call',
            'id': 'fc_1',
            'call_id': 'call_1',
            'name': 'search',
            'arguments': '{"q":"x"}',
          },
        ],
      });
      expect(raw, isNotNull);
      final items = raw!['output'] as List;
      expect(items, hasLength(3));
      expect(items[0]['type'], 'reasoning');
      expect(items[1]['type'], 'message');
      expect((items[2] as Map)['call_id'], 'call_1');
    });

    test('空 output 返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {'output': []});
      expect(raw, isNull);
    });
  });

  group('ResponsesAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = ResponsesAdapter();

    test('从 snapshot 拼出 output 列表（reasoning → message → function_call）', () {
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'final',
          reasoning: 'think',
          toolCalls: [
            StreamingToolCallDraft(
              id: 'fc_1',
              toolName: 'search',
              argumentsBuffer: '{"q":"x"}',
              sequence: 0,
              isDone: true,
            ),
          ],
          providerState: {'response_id': 'resp_1'},
        ),
      );
      expect(raw, isNotNull);
      final items = raw!['output'] as List;
      expect(items[0]['type'], 'reasoning');
      expect(items[1]['type'], 'message');
      expect(((items[1]['content'] as List).first as Map)['text'], 'final');
      expect(items[2]['type'], 'function_call');
      expect((items[2] as Map)['call_id'], 'fc_1');
    });

    test('完全空 snapshot 返回 null', () {
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: null,
          reasoning: null,
          toolCalls: [],
          providerState: {},
        ),
      );
      expect(raw, isNull);
    });
  });

  group('ResponsesAdapter.buildPlannerPayloadFromCarriers', () {
    const adapter = ResponsesAdapter();

    test('system → instructions; user → input_text; raw.output → 直接注入 input', () {
      const raw = {
        'output': [
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
        availableTools: const [],
        parallelToolCalls: false,
      );
      expect(payload['instructions'], 'agent');
      final input = payload['input'] as List;
      expect(input, hasLength(4));
      expect(input[0]['type'], 'message');
      expect(input[0]['role'], 'user');
      expect(input[1], raw['output']![0]);
      expect(input[2], raw['output']![1]);
      expect(input[3]['type'], 'function_call_output');
      expect(input[3]['call_id'], 'call_1');
      expect(input[3]['output'], 'OK');
    });

    test('tools 转 Responses 形 function 描述', () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [SyntheticCarrier.user('hi')],
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
      final tools = payload['tools'] as List;
      expect(tools.first['type'], 'function');
      expect(tools.first['name'], 'search');
      expect(tools.first['parameters'], {'type': 'object'});
    });

    test('attachment-only user carrier serializes input_image in planner payload',
        () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: [
          SyntheticCarrier.user(
            '',
            attachments: [
              ChatAttachment.image(
                localId: 'att-1',
                fileName: 'demo.png',
                mimeType: 'image/png',
                status: ChatAttachmentStatus.ready,
                providerFileRefJson: const {
                  'data_url': 'data:image/png;base64,AAAA',
                },
              ),
            ],
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-5',
        availableTools: const [],
        parallelToolCalls: false,
      );

      final input = payload['input'] as List;
      final content = input.single['content'] as List;
      expect(content.any((item) => item['type'] == 'input_image'), isTrue);
    });
  });
}
