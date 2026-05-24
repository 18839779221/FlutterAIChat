import 'package:openai_dart/openai_dart.dart' as oai;

/// Provider-execution request specification produced by protocol adapters.
///
/// Adapters own semantic mapping from planner carriers / chat messages into
/// provider-native request objects. Runtimes consume these specs to execute
/// requests without needing to understand upper-layer semantics.
sealed class ProtocolRequestSpec {
  const ProtocolRequestSpec();
}

/// Request spec for protocols still executed through raw JSON HTTP calls.
class JsonProtocolRequestSpec extends ProtocolRequestSpec {
  const JsonProtocolRequestSpec({
    required this.payload,
    required this.headers,
  });

  /// Fully materialized provider payload.
  final Map<String, dynamic> payload;

  /// Provider-specific request headers.
  final Map<String, String> headers;
}

/// Request spec for OpenAI-compatible Chat Completions SDK execution.
class ChatCompletionsRequestSpec extends ProtocolRequestSpec {
  const ChatCompletionsRequestSpec({
    required this.request,
  });

  /// Typed chat completions request passed directly to `openai_dart`.
  final oai.ChatCompletionCreateRequest request;
}

/// Request spec for OpenAI Responses SDK execution.
class ResponsesRequestSpec extends ProtocolRequestSpec {
  const ResponsesRequestSpec({
    required this.request,
  });

  /// Typed responses request passed directly to `openai_dart`.
  final oai.CreateResponseRequest request;
}
