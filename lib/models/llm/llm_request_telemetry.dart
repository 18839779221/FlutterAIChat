import 'llm_cache_strategy.dart';
import 'llm_cache_usage.dart';

/// File-log telemetry for one outbound LLM request.
class LlmRequestTelemetry {
  /// Stable request label such as planner or side_summary.
  final String label;

  /// Protocol style name used for the request.
  final String apiStyle;

  /// Model name sent upstream.
  final String modelName;

  /// Purpose of the request.
  final String purpose;

  /// Estimated input token count before sending.
  final int estimatedInputTokens;

  /// Message count used to build the payload.
  final int messageCount;

  /// Serialized payload size in bytes.
  final int payloadBytes;

  /// First streamed chunk latency in milliseconds.
  final int? firstChunkMs;

  /// Total request latency in milliseconds.
  final int totalMs;

  /// Retry attempt number, starting at 1.
  final int attempt;

  /// Cache mode used for this request.
  final LlmCacheStrategy cacheStrategy;

  /// Normalized provider usage data, when available.
  final LlmCacheUsage? cacheUsage;

  const LlmRequestTelemetry({
    required this.label,
    required this.apiStyle,
    required this.modelName,
    required this.purpose,
    required this.estimatedInputTokens,
    required this.messageCount,
    required this.payloadBytes,
    required this.firstChunkMs,
    required this.totalMs,
    required this.attempt,
    required this.cacheStrategy,
    required this.cacheUsage,
  });
}
