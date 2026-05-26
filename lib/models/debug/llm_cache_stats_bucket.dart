import 'llm_cache_stats_summary.dart';

/// Summary bucket used to compare cache hit metrics by one grouping key.
class LlmCacheStatsBucket {
  final String key;
  final LlmCacheStatsSummary summary;

  const LlmCacheStatsBucket({
    required this.key,
    required this.summary,
  });
}
