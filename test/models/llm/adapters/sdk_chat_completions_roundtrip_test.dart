import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkChatCompletionsAdapter.extractRawAssistantMessage', () {
    const adapter = SdkChatCompletionsAdapter();

    test('保留 content + tool_calls + reasoning_content 三类字段', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'resp_1',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Let me search',
              'reasoning_content': 'think first',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'search', 'arguments': '{"q":"x"}'},
                },
              ],
            },
          },
        ],
      });
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      expect(raw['content'], 'Let me search');
      expect(raw['reasoning_content'], 'think first');
      expect((raw['tool_calls'] as List).first['id'], 'call_1');
    });

    test('空 choices 返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {'choices': []});
      expect(raw, isNull);
    });

    test('未来 provider 新增字段也透传', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': 'hi',
              'future_provider_field': 'whatever',
            },
          },
        ],
      });
      expect(raw!['future_provider_field'], 'whatever');
    });
  });

  group('SdkChatCompletionsAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = SdkChatCompletionsAdapter();

    test('累积 text + reasoning + 一条 tool_call 拼成完整 message', () {
      const snapshot = StreamingDecisionAccumulatorSnapshot(
        text: 'final',
        reasoning: 'why',
        toolCalls: [
          StreamingToolCallDraft(
            id: 'c1',
            toolName: 's',
            argumentsBuffer: '{"q":"x"}',
            sequence: 0,
            isDone: true,
          ),
        ],
        providerState: {},
      );
      final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      expect(raw['content'], 'final');
      expect(raw['reasoning_content'], 'why');
      final tc = (raw['tool_calls'] as List).first as Map;
      expect(tc['id'], 'c1');
      expect(tc['type'], 'function');
      expect((tc['function'] as Map)['arguments'], '{"q":"x"}');
    });

    test('text-only snapshot 不输出 tool_calls 字段', () {
      const snapshot = StreamingDecisionAccumulatorSnapshot(
        text: 'hi',
        reasoning: null,
        toolCalls: [],
        providerState: {},
      );
      final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
      expect(raw, isNotNull);
      expect(raw!['content'], 'hi');
      expect(raw.containsKey('tool_calls'), isFalse);
      expect(raw.containsKey('reasoning_content'), isFalse);
    });

    test('完全空 snapshot 返回 null', () {
      const snapshot = StreamingDecisionAccumulatorSnapshot(
        text: null,
        reasoning: null,
        toolCalls: [],
        providerState: {},
      );
      expect(adapter.assembleRawFromStreamingSnapshot(snapshot), isNull);
    });
  });

  group('SdkChatCompletionsAdapter.buildPlannerPayloadFromCarriers', () {
    const adapter = SdkChatCompletionsAdapter();

    test('raw assistant 在 messages 中逐字节相等', () {
      const raw = {
        'role': 'assistant',
        'content': 'Let me search',
        'reasoning_content': 'think first',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'search', 'arguments': '{"q":"x"}'},
          },
        ],
      };
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [
          SyntheticCarrier.system('You are an agent.'),
          SyntheticCarrier.user('please search x'),
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
            rawJson: raw,
          ),
          SyntheticCarrier.toolResult(toolCallId: 'call_1', content: 'OK'),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'deepseek-chat',
        availableTools: const [],
        parallelToolCalls: false,
      );
      final messages = payload['messages'] as List;
      expect(messages, hasLength(4));
      expect(messages[0], {'role': 'system', 'content': 'You are an agent.'});
      expect(messages[1], {'role': 'user', 'content': 'please search x'});
      expect(messages[2], raw);
      expect(messages[3], {
        'role': 'tool',
        'tool_call_id': 'call_1',
        'content': 'OK',
      });
    });

    test('deepseek 模型不带 parallel_tool_calls 字段', () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [SyntheticCarrier.user('hi')],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'deepseek-chat',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 's',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );
      expect(payload.containsKey('parallel_tool_calls'), isFalse);
      expect(payload['tools'], isA<List>());
      expect(payload['tool_choice'], 'auto');
    });

    test('非 deepseek 模型带 parallel_tool_calls 字段', () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [SyntheticCarrier.user('hi')],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-4o',
        availableTools: const [
          PlannerToolOption(
            name: 'search',
            description: 's',
            inputSchema: {'type': 'object'},
          ),
        ],
        parallelToolCalls: true,
      );
      expect(payload['parallel_tool_calls'], true);
    });

    test('no tools → 不带 tools / tool_choice / parallel_tool_calls', () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [SyntheticCarrier.user('hi')],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'gpt-4o',
        availableTools: const [],
        parallelToolCalls: true,
      );
      expect(payload.containsKey('tools'), isFalse);
      expect(payload.containsKey('tool_choice'), isFalse);
      expect(payload.containsKey('parallel_tool_calls'), isFalse);
    });
  });
}
