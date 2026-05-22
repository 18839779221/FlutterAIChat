/// Estimates token count from a provider's raw assistant message JSON.
///
/// Intentionally tolerant: only sums characters from fields that all three
/// supported providers (OpenAI/DeepSeek/Anthropic) commonly use. Unknown
/// fields are ignored — a future provider field costs at most a small token
/// undercount, never a crash.
class RawAssistantTokenEstimator {
  const RawAssistantTokenEstimator();

  int estimate(Map<String, dynamic> rawJson) {
    var chars = 0;

    final content = rawJson['content'];
    if (content is String) {
      chars += content.length;
    } else if (content is List) {
      for (final part in content) {
        if (part is Map) {
          final text = part['text'];
          if (text is String) chars += text.length;
        }
      }
    }

    final reasoning = rawJson['reasoning_content'];
    if (reasoning is String) chars += reasoning.length;

    final toolCalls = rawJson['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final fn = tc['function'];
        if (fn is! Map) continue;
        final args = fn['arguments'];
        if (args is String) chars += args.length;
      }
    }

    return chars ~/ 4;
  }
}
