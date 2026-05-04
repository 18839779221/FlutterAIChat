import 'llm_cache_strategy.dart';

/// Request-scoped cache controls derived from runtime config.
class LlmCacheRequestOptions {
  /// The cache mode for this request.
  final LlmCacheStrategy strategy;

  /// Stable cache routing key for providers that accept one.
  final String? cacheKey;

  /// Optional provider-specific retention hint.
  final String? retention;

  /// Whether stable system/tool prefix blocks may be marked cacheable.
  final bool markStableSystemPrefix;

  const LlmCacheRequestOptions({
    this.strategy = LlmCacheStrategy.observeOnly,
    this.cacheKey,
    this.retention,
    this.markStableSystemPrefix = false,
  });
}
