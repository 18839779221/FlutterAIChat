/// Normalized cache usage extracted from a provider response.
class LlmCacheUsage {
  /// Provider-reported input tokens.
  final int? inputTokens;

  /// Provider-reported output tokens.
  final int? outputTokens;

  /// OpenAI-style cached input tokens.
  final int? cachedInputTokens;

  /// Anthropic-style cache read tokens.
  final int? cacheReadInputTokens;

  /// Anthropic-style cache write tokens.
  final int? cacheWriteInputTokens;

  /// DeepSeek-like cache miss tokens.
  final int? cacheMissInputTokens;

  /// Raw usage object preserved for debugging.
  final Map<String, dynamic> rawUsage;

  const LlmCacheUsage({
    this.inputTokens,
    this.outputTokens,
    this.cachedInputTokens,
    this.cacheReadInputTokens,
    this.cacheWriteInputTokens,
    this.cacheMissInputTokens,
    this.rawUsage = const {},
  });
}
