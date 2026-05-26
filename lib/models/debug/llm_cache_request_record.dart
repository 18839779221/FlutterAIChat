/// Parsed cache-related facts for one `llm.request.done` trace entry.
class LlmCacheRequestRecord {
  final DateTime timestamp;
  final String? apiStyle;
  final String? modelName;
  final String? purpose;
  final String? cacheStrategy;
  final int? estimatedInputTokens;
  final int? inputTokens;
  final int? cachedInputTokens;
  final int? cacheReadInputTokens;
  final int? cacheWriteInputTokens;
  final int? cacheMissInputTokens;
  final int? totalMs;
  final int? firstChunkMs;

  const LlmCacheRequestRecord({
    required this.timestamp,
    this.apiStyle,
    this.modelName,
    this.purpose,
    this.cacheStrategy,
    this.estimatedInputTokens,
    this.inputTokens,
    this.cachedInputTokens,
    this.cacheReadInputTokens,
    this.cacheWriteInputTokens,
    this.cacheMissInputTokens,
    this.totalMs,
    this.firstChunkMs,
  });
}
