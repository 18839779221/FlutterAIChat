/// Aggregate cache hit metrics for a group of LLM requests.
class LlmCacheStatsSummary {
  final int totalRequests;
  final int requestsWithUsage;
  final int hitRequests;
  final int totalInputTokens;
  final int hitInputTokens;

  const LlmCacheStatsSummary({
    required this.totalRequests,
    required this.requestsWithUsage,
    required this.hitRequests,
    required this.totalInputTokens,
    required this.hitInputTokens,
  });

  double get requestHitRate {
    if (requestsWithUsage <= 0) {
      return 0;
    }
    return hitRequests / requestsWithUsage;
  }

  double get tokenHitRate {
    if (totalInputTokens <= 0) {
      return 0;
    }
    return hitInputTokens / totalInputTokens;
  }
}
