import 'package:ai_chat/models/llm/llm_usage_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts OpenAI Responses cached tokens', () {
    final usage = LlmUsageExtractor.extract({
      'usage': {
        'input_tokens': 120,
        'output_tokens': 40,
        'input_tokens_details': {'cached_tokens': 96},
      },
    });

    expect(usage?.inputTokens, 120);
    expect(usage?.outputTokens, 40);
    expect(usage?.cachedInputTokens, 96);
  });

  test('extracts OpenAI Chat Completions cached tokens', () {
    final usage = LlmUsageExtractor.extract({
      'usage': {
        'prompt_tokens': 88,
        'completion_tokens': 12,
        'prompt_tokens_details': {'cached_tokens': 64},
      },
    });

    expect(usage?.inputTokens, 88);
    expect(usage?.outputTokens, 12);
    expect(usage?.cachedInputTokens, 64);
  });

  test('extracts Anthropic cache usage fields', () {
    final usage = LlmUsageExtractor.extract({
      'usage': {
        'input_tokens': 150,
        'output_tokens': 55,
        'cache_read_input_tokens': 110,
        'cache_creation_input_tokens': 40,
      },
    });

    expect(usage?.inputTokens, 150);
    expect(usage?.outputTokens, 55);
    expect(usage?.cacheReadInputTokens, 110);
    expect(usage?.cacheWriteInputTokens, 40);
  });

  test('extracts DeepSeek-like cache usage fields', () {
    final usage = LlmUsageExtractor.extract({
      'usage': {
        'prompt_tokens': 200,
        'completion_tokens': 20,
        'prompt_cache_hit_tokens': 160,
        'prompt_cache_miss_tokens': 40,
      },
    });

    expect(usage?.inputTokens, 200);
    expect(usage?.outputTokens, 20);
    expect(usage?.cacheReadInputTokens, 160);
    expect(usage?.cacheMissInputTokens, 40);
  });

  test('returns null when usage is absent', () {
    expect(LlmUsageExtractor.extract({}), isNull);
  });
}
