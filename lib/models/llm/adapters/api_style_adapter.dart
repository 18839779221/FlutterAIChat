import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_request_purpose.dart';
import '../llm_request_options.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../runtime/protocol_request_spec.dart';
import '../streaming_decision_accumulator.dart';
import '../../agent/model_turn_decision.dart';
import 'provider_capabilities.dart';

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

  /// Declares orchestration-relevant provider capabilities.
  ProviderCapabilities get capabilities;

  /// Request headers retained for legacy JSON runtime compatibility.
  Map<String, String> buildHeaders(LLMConfig runtimeConfig);

  /// Normalize request-scoped options according to provider-specific policy.
  ///
  /// This keeps orchestration generic while allowing adapters to enforce
  /// provider-contract defaults such as planner reasoning toggles.
  LlmRequestOptions normalizeRequestOptions(
    LlmRequestOptions requestOptions, {
    required LlmRequestPurpose purpose,
  }) {
    return requestOptions;
  }

  /// Build the primary chat request for direct model-side tasks.
  ProtocolRequestSpec buildChatRequestSpec({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    required LLMConfig runtimeConfig,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  });

  /// Legacy JSON payload builder kept for compatibility during runtime split.
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

  /// Parse a provider response into a terminal or tool-use
  /// [ModelTurnDecision].
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload);

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

  /// Build the planner request spec from a list of carriers. RawAssistant
  /// carriers are spliced byte-identically; Synthetic carriers are
  /// materialized using the adapter's role mapping.
  ProtocolRequestSpec buildPlannerRequestSpecFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    required LLMConfig runtimeConfig,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  });

  /// Legacy JSON planner payload builder kept for compatibility during
  /// runtime split and focused adapter tests.
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  });
}
