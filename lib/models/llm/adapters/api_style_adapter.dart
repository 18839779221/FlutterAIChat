import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_request_options.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../streaming_decision_accumulator.dart';

/// Encapsulates the differences between the three supported HTTP LLM
/// protocols. `ConfigurableHttpLLM` stays protocol-agnostic and dispatches to
/// an [ApiStyleAdapter] per [ApiStyle].
///
/// Architecture:
/// - docs/architecture/append-only-transcript.md
///
/// Invariant:
/// - adapters only serialize transcript replay for planner requests
/// - provider protocol details must not reintroduce native continuation state
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

  /// Parse a structured planner response into a [PlannerToolChoice], or null
  /// if the response isn't decodable.
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload);

  /// Extract plain text from a non-streaming response body (used by
  /// `_sendTextRequest`).
  String extractNonStreamText(Map<String, dynamic> payload);

  /// Extract the raw assistant message JSON from a non-streaming planner
  /// response, preserving every provider-specific field for verbatim replay
  /// on the next outbound request. Returns null when the response carries no
  /// assistant content (empty choices, etc.).
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  );

  /// Assemble a provider-shaped raw assistant message JSON from the streaming
  /// accumulator's current state. Each adapter knows how to merge text,
  /// reasoning, and tool_calls into its provider's wire shape.
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  );

  /// Build the planner request payload from a list of carriers. RawAssistant
  /// carriers are spliced byte-identically; Synthetic carriers are
  /// materialized using the adapter's role mapping.
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  });
}
