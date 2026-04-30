import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../llm_request_options.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';

/// Encapsulates the differences between the three supported HTTP LLM
/// protocols. `ConfigurableHttpLLM` stays protocol-agnostic and dispatches to
/// an [ApiStyleAdapter] per [ApiStyle].
abstract class ApiStyleAdapter {
  const ApiStyleAdapter();

  ApiStyle get style;

  /// Request headers for both chat and planner calls.
  Map<String, String> buildHeaders(LLMConfig runtimeConfig);

  /// Build the primary chat payload for `chatStream` / `validateApiKey`.
  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  });

  /// Build the structured-planner payload used by `planTurnDecision`.
  Map<String, dynamic> buildPlannerPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems = const [],
    Map<String, dynamic>? providerState,
  });

  /// Parse a structured planner response into a [PlannerToolChoice], or null
  /// if the response isn't decodable.
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload);

  /// Extract plain text from a non-streaming response body (used by
  /// `_sendTextRequest`).
  String extractNonStreamText(Map<String, dynamic> payload);
}
