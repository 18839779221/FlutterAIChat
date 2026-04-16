import 'model_tool_call.dart';
import '../chat_turn.dart';

/// Normalized provider decision for one model turn before tool execution.
///
/// A single provider turn may contain both visible assistant text and one or
/// more tool calls. `assistantMessage` therefore represents intermediate-capable
/// model output, not only a final answer.
class ModelTurnDecision {
  final List<ModelToolCall> toolCalls;
  final String? assistantMessage;

  /// Planner diagnostic code preserved when compatibility layers translate
  /// legacy planner actions into provider-native decisions.
  final String? diagnosticCode;

  /// Provider-specific continuation state preserved across tool loops.
  final Map<String, dynamic> providerState;

  /// Runtime provider style used for this decision.
  final ChatTurnProviderStyle? providerStyle;

  /// Runtime model name used when requesting this decision.
  final String? modelName;

  /// Whether the provider considers this turn terminal for planner purposes.
  ///
  /// Terminal means no additional planner loop is required from this decision;
  /// it does not imply that `assistantMessage` is the final user-facing answer.
  final bool isTerminal;

  const ModelTurnDecision({
    required this.toolCalls,
    required this.assistantMessage,
    this.diagnosticCode,
    required this.providerState,
    this.providerStyle,
    this.modelName,
    required this.isTerminal,
  });

  ModelTurnDecision copyWith({
    List<ModelToolCall>? toolCalls,
    String? assistantMessage,
    String? diagnosticCode,
    Map<String, dynamic>? providerState,
    ChatTurnProviderStyle? providerStyle,
    String? modelName,
    bool? isTerminal,
  }) {
    return ModelTurnDecision(
      toolCalls: toolCalls ?? this.toolCalls,
      assistantMessage: assistantMessage ?? this.assistantMessage,
      diagnosticCode: diagnosticCode ?? this.diagnosticCode,
      providerState: providerState ?? this.providerState,
      providerStyle: providerStyle ?? this.providerStyle,
      modelName: modelName ?? this.modelName,
      isTerminal: isTerminal ?? this.isTerminal,
    );
  }
}
