import 'llm_cache_request_record.dart';
import 'llm_cache_stats_bucket.dart';
import 'llm_cache_stats_summary.dart';

/// Read-only data consumed by the debug cache statistics panel.
class DebugCachePanelProjection {
  final int sampleSize;
  final String? sourceLogPath;
  final LlmCacheStatsSummary summary;
  final List<LlmCacheStatsBucket> bucketsByApiStyle;
  final List<LlmCacheRequestRecord> recentRequests;
  final String? warningMessage;

  const DebugCachePanelProjection({
    required this.sampleSize,
    required this.sourceLogPath,
    required this.summary,
    required this.bucketsByApiStyle,
    required this.recentRequests,
    this.warningMessage,
  });
}
