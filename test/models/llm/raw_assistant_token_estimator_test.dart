import 'package:ai_chat/models/llm/raw_assistant_token_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const estimator = RawAssistantTokenEstimator();

  test('累加 content 字符数', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': 'hello world',
    });
    expect(tokens, 'hello world'.length ~/ 4);
  });

  test('累加 reasoning_content', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': 'final answer',
      'reasoning_content': 'think hard',
    });
    expect(tokens, ('final answer'.length + 'think hard'.length) ~/ 4);
  });

  test('累加 tool_calls function.arguments', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'id': 'c1',
          'function': {'name': 'search', 'arguments': '{"q":"x"}'},
        },
      ],
    });
    expect(tokens, '{"q":"x"}'.length ~/ 4);
  });

  test('content 是 list 形（Anthropic）抽 text 字段累加', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': 'first part'},
        {'type': 'text', 'text': 'second part'},
      ],
    });
    expect(tokens, ('first part'.length + 'second part'.length) ~/ 4);
  });

  test('未知字段忽略，不报错', () {
    final tokens = estimator.estimate(const {
      'role': 'assistant',
      'content': 'hi',
      'future_provider_field': 'whatever',
    });
    expect(tokens, 'hi'.length ~/ 4);
  });

  test('空 map 返回 0', () {
    expect(estimator.estimate(const {}), 0);
  });
}
