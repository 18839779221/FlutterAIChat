import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
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
}
