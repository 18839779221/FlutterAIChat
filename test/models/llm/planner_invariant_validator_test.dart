import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/planner_invariant_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = PlannerInvariantValidator();
  const active = ChatTurnProviderStyle.openaiChatCompletions;

  test('全 synthetic 列表通过', () {
    validator.validate(
      carriers: const [
        SyntheticCarrier.system('sys'),
        SyntheticCarrier.user('hi'),
      ],
      activeApiStyle: active,
      currentTurnRunning: false,
    );
  });

  test('raw apiStyle 不匹配抛 InconsistentProviderStateError', () {
    expect(
      () => validator.validate(
        carriers: const [
          SyntheticCarrier.user('hi'),
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.anthropicMessages,
            rawJson: {'role': 'assistant'},
          ),
        ],
        activeApiStyle: active,
        currentTurnRunning: false,
      ),
      throwsA(isA<InconsistentProviderStateError>()),
    );
  });

  test('completed turn 中 tool_call 必须有配对 toolResult', () {
    expect(
      () => validator.validate(
        carriers: const [
          SyntheticCarrier.user('hi'),
          RawAssistantCarrier(
            apiStyle: active,
            rawJson: {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'function': {'name': 's', 'arguments': '{}'},
                },
              ],
            },
          ),
        ],
        activeApiStyle: active,
        currentTurnRunning: false,
      ),
      throwsA(isA<ToolCallPairingError>()),
    );
  });

  test('running turn 允许 tool_call 暂未配对', () {
    validator.validate(
      carriers: const [
        SyntheticCarrier.user('hi'),
        RawAssistantCarrier(
          apiStyle: active,
          rawJson: {
            'role': 'assistant',
            'tool_calls': [
              {
                'id': 'call_1',
                'function': {'name': 's', 'arguments': '{}'},
              },
            ],
          },
        ),
      ],
      activeApiStyle: active,
      currentTurnRunning: true,
    );
  });

  test('多 tool_calls 全部配对通过', () {
    validator.validate(
      carriers: const [
        SyntheticCarrier.user('hi'),
        RawAssistantCarrier(
          apiStyle: active,
          rawJson: {
            'role': 'assistant',
            'tool_calls': [
              {
                'id': 'c1',
                'function': {'name': 's', 'arguments': '{}'},
              },
              {
                'id': 'c2',
                'function': {'name': 's', 'arguments': '{}'},
              },
            ],
          },
        ),
        SyntheticCarrier.toolResult(toolCallId: 'c1', content: 'r1'),
        SyntheticCarrier.toolResult(toolCallId: 'c2', content: 'r2'),
      ],
      activeApiStyle: active,
      currentTurnRunning: false,
    );
  });

  test('Anthropic 形 raw（content list 中的 tool_use）也参与配对', () {
    expect(
      () => validator.validate(
        carriers: const [
          SyntheticCarrier.user('hi'),
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.anthropicMessages,
            rawJson: {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'let me'},
                {'type': 'tool_use', 'id': 'toolu_1', 'name': 's', 'input': {}},
              ],
            },
          ),
        ],
        activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
        currentTurnRunning: false,
      ),
      throwsA(isA<ToolCallPairingError>()),
    );
  });

  test('Responses 形 raw（output 中的 function_call）也参与配对', () {
    expect(
      () => validator.validate(
        carriers: const [
          SyntheticCarrier.user('hi'),
          RawAssistantCarrier(
            apiStyle: ChatTurnProviderStyle.openaiResponses,
            rawJson: {
              'output': [
                {
                  'type': 'function_call',
                  'call_id': 'fc_1',
                  'name': 's',
                  'arguments': '{}',
                },
              ],
            },
          ),
        ],
        activeApiStyle: ChatTurnProviderStyle.openaiResponses,
        currentTurnRunning: false,
      ),
      throwsA(isA<ToolCallPairingError>()),
    );
  });
}
