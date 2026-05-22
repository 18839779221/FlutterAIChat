import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/adapters/anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnthropicMessagesAdapter.extractRawAssistantMessage', () {
    const adapter = AnthropicMessagesAdapter();

    test('保留 content 列表（thinking + text + tool_use）', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'msg_1',
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': 'plan', 'signature': 'sig_xyz'},
          {'type': 'text', 'text': 'Let me search'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'search',
            'input': {'q': 'x'},
          },
        ],
      });
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      final blocks = raw['content'] as List;
      expect(blocks.length, 3);
      expect(blocks[0]['signature'], 'sig_xyz');
      expect(blocks[2]['id'], 'toolu_1');
    });

    test('content 空列表返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'role': 'assistant',
        'content': [],
      });
      expect(raw, isNull);
    });

    test('role 非 assistant 返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'hi'},
        ],
      });
      expect(raw, isNull);
    });
  });

  group('AnthropicMessagesAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = AnthropicMessagesAdapter();

    test('reasoning + text + tool_use 拼成 content blocks 列表（顺序：thinking → text → tool_use）', () {
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'searching',
          reasoning: 'think',
          toolCalls: [
            StreamingToolCallDraft(
              id: 'toolu_1',
              toolName: 'search',
              argumentsBuffer: '{"q":"x"}',
              sequence: 0,
              isDone: true,
            ),
          ],
          providerState: {'anthropic_thinking_signature': 'sig_z'},
        ),
      );
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      final blocks = raw['content'] as List;
      expect(blocks[0]['type'], 'thinking');
      expect(blocks[0]['thinking'], 'think');
      expect(blocks[0]['signature'], 'sig_z');
      expect(blocks[1]['type'], 'text');
      expect(blocks[1]['text'], 'searching');
      expect(blocks[2]['type'], 'tool_use');
      expect(blocks[2]['id'], 'toolu_1');
      expect(blocks[2]['name'], 'search');
      expect(blocks[2]['input'], {'q': 'x'});
    });

    test('text-only snapshot 只输出 text block', () {
      final raw = adapter.assembleRawFromStreamingSnapshot(
        const StreamingDecisionAccumulatorSnapshot(
          text: 'hi',
          reasoning: null,
          toolCalls: [],
          providerState: {},
        ),
      );
      expect(raw, isNotNull);
      final blocks = raw!['content'] as List;
      expect(blocks.length, 1);
      expect(blocks[0]['type'], 'text');
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

  group('AnthropicMessagesAdapter.buildPlannerPayloadFromCarriers', () {
    const adapter = AnthropicMessagesAdapter();

    test('system 提到顶层, user/toolResult/raw 落到 messages 数组', () {
      const raw = {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Let me search'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'search',
            'input': {'q': 'x'},
          },
        ],
      };
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [
          SyntheticCarrier.system('agent'),
          SyntheticCarrier.user('please'),
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.anthropicMessages,
            rawJson: raw,
          ),
          SyntheticCarrier.toolResult(toolCallId: 'toolu_1', content: 'OK'),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude-3-5-sonnet',
        availableTools: const [],
        parallelToolCalls: false,
      );
      expect(payload['system'], 'agent');
      final messages = payload['messages'] as List;
      expect(messages, hasLength(3));
      expect(messages[0]['role'], 'user');
      expect((messages[0]['content'] as List).first['text'], 'please');
      expect(messages[1], raw);
      expect(messages[2]['role'], 'user');
      final toolResultBlock = (messages[2]['content'] as List).first as Map;
      expect(toolResultBlock['type'], 'tool_result');
      expect(toolResultBlock['tool_use_id'], 'toolu_1');
      expect(toolResultBlock['content'], 'OK');
    });

    test('多 system carrier 拼接', () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [
          SyntheticCarrier.system('first'),
          SyntheticCarrier.system('second'),
          SyntheticCarrier.user('hi'),
        ],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude-3-5-sonnet',
        availableTools: const [],
        parallelToolCalls: false,
      );
      expect(payload['system'], 'first\n\nsecond');
    });

    test('tools 转 input_schema 形状', () {
      final payload = adapter.buildPlannerPayloadFromCarriers(
        carriers: const [SyntheticCarrier.user('hi')],
        config: ChatConfig(systemPrompt: ''),
        modelName: 'claude-3-5-sonnet',
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
      expect(tools.first['name'], 'search');
      expect(tools.first['description'], 'web search');
      expect(tools.first['input_schema'], {'type': 'object'});
    });
  });
}
