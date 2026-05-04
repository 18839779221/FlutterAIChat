import 'llm_cache_request_options.dart';

/// Request-scoped options derived from runtime model budgets and call intent.
class LlmRequestOptions {
  /// Max tokens the upstream API may spend on output for this request.
  final int? maxOutputTokens;

  /// Whether provider-side hidden thinking / reasoning should stay enabled.
  final bool allowReasoning;

  /// Cache-related request controls for this call.
  final LlmCacheRequestOptions cache;

  const LlmRequestOptions({
    this.maxOutputTokens,
    this.allowReasoning = true,
    this.cache = const LlmCacheRequestOptions(),
  });
}
