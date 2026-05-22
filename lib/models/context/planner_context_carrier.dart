import '../chat_turn.dart';
import '../llm/raw_assistant_token_estimator.dart';

/// Role of a synthetic (our-side) carrier.
///
/// Provider-captured assistant turns use [RawAssistantCarrier] instead.
enum SyntheticRole { system, user, toolResult }

/// One element in the planner request context.
///
/// Sealed so that adapters can switch over the closed set when materializing
/// carriers into provider wire format.
sealed class PlannerContextCarrier {
  const PlannerContextCarrier();

  /// Rough token estimate used by [SessionTokenBudgetService].
  int get estimatedTokens;
}

/// A carrier produced by our side: system prompts, user inputs, tool results,
/// runtime context, compaction snapshot summaries.
///
/// Adapters convert these into the provider's wire shape using their own
/// knowledge of role mapping.
class SyntheticCarrier extends PlannerContextCarrier {
  final SyntheticRole role;
  final String content;
  final String? toolCallId;

  const SyntheticCarrier._({
    required this.role,
    required this.content,
    this.toolCallId,
  });

  const SyntheticCarrier.system(String content)
      : this._(role: SyntheticRole.system, content: content);

  const SyntheticCarrier.user(String content)
      : this._(role: SyntheticRole.user, content: content);

  const SyntheticCarrier.toolResult({
    required String toolCallId,
    required String content,
  }) : this._(
          role: SyntheticRole.toolResult,
          content: content,
          toolCallId: toolCallId,
        );

  @override
  int get estimatedTokens => content.length ~/ 4;
}

/// A previous assistant turn captured at parse time, stored verbatim in the
/// provider's wire shape.
///
/// Adapters splice [rawJson] into outbound requests byte-identically. The
/// [apiStyle] guards against cross-provider message smuggling.
class RawAssistantCarrier extends PlannerContextCarrier {
  final ChatTurnProviderStyle apiStyle;
  final Map<String, dynamic> rawJson;

  const RawAssistantCarrier({
    required this.apiStyle,
    required this.rawJson,
  });

  static const _estimator = RawAssistantTokenEstimator();

  @override
  int get estimatedTokens => _estimator.estimate(rawJson);
}
