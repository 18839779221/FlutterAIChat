import 'llm_cache_usage.dart';

/// Normalizes provider usage payloads into a shared cache-aware shape.
class LlmUsageExtractor {
  const LlmUsageExtractor();

  /// Extracts cache-aware usage from a decoded response payload.
  static LlmCacheUsage? extract(Map<String, dynamic> payload) {
    final usage = payload['usage'];
    if (usage is! Map) {
      return null;
    }
    final normalized = usage.cast<String, dynamic>();
    return LlmCacheUsage(
      inputTokens: _readInt(
        normalized,
        const ['input_tokens', 'prompt_tokens'],
      ),
      outputTokens: _readInt(
        normalized,
        const ['output_tokens', 'completion_tokens'],
      ),
      cachedInputTokens: _readInt(
        normalized,
        const [
          'input_tokens_details.cached_tokens',
          'prompt_tokens_details.cached_tokens',
          'cached_tokens',
        ],
      ),
      cacheReadInputTokens: _readInt(
        normalized,
        const [
          'cache_read_input_tokens',
          'prompt_cache_hit_tokens',
        ],
      ),
      cacheWriteInputTokens: _readInt(
        normalized,
        const [
          'cache_creation_input_tokens',
          'prompt_cache_write_tokens',
        ],
      ),
      cacheMissInputTokens: _readInt(
        normalized,
        const [
          'prompt_cache_miss_tokens',
        ],
      ),
      rawUsage: Map<String, dynamic>.from(normalized),
    );
  }

  static int? _readInt(Map<String, dynamic> usage, List<String> paths) {
    for (final path in paths) {
      final value = _readPath(usage, path);
      final parsed = _toInt(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static dynamic _readPath(Map<String, dynamic> source, String path) {
    final segments = path.split('.');
    dynamic current = source;
    for (final segment in segments) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
      if (current == null) {
        return null;
      }
    }
    return current;
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
