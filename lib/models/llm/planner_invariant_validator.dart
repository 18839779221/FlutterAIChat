import '../chat_turn.dart';
import '../context/planner_context_carrier.dart';

/// Thrown when a [RawAssistantCarrier] has a different [apiStyle] than the
/// active provider. Should be unreachable through the UI once provider lock
/// is enforced at group creation.
class InconsistentProviderStateError extends StateError {
  InconsistentProviderStateError(super.message);
}

/// Thrown when a completed turn has a tool_call whose tool_call_id is never
/// resolved by a matching tool result. Catches the DeepSeek 400 root cause
/// before the request leaves the device.
class ToolCallPairingError extends StateError {
  ToolCallPairingError(super.message);
}

/// Validates the planner contract on a list of [PlannerContextCarrier] before
/// the adapter materializes them into wire format.
///
/// Two invariants enforced:
///   1. Every [RawAssistantCarrier.apiStyle] matches the active provider.
///   2. Every tool_call_id introduced by a [RawAssistantCarrier] is later
///      resolved by a [SyntheticCarrier] with [SyntheticRole.toolResult] and
///      the matching toolCallId — UNLESS the in-progress turn is still
///      running (e.g. AskUserQuestion is waiting for the user).
class PlannerInvariantValidator {
  const PlannerInvariantValidator();

  void validate({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
  }) {
    final pending = <String>{};

    for (var i = 0; i < carriers.length; i++) {
      final c = carriers[i];

      switch (c) {
        case RawAssistantCarrier(:final apiStyle, :final rawJson):
          if (apiStyle != activeApiStyle) {
            throw InconsistentProviderStateError(
              'carriers[$i] apiStyle=$apiStyle but active=$activeApiStyle',
            );
          }
          pending.addAll(_extractToolCallIds(apiStyle: apiStyle, rawJson: rawJson));

        case SyntheticCarrier(
              role: SyntheticRole.toolResult,
              :final toolCallId,
            ):
          if (toolCallId != null) pending.remove(toolCallId);

        case SyntheticCarrier():
          break;
      }
    }

    if (!currentTurnRunning && pending.isNotEmpty) {
      throw ToolCallPairingError(
        'unpaired tool_call_ids: ${pending.toList()}',
      );
    }
  }

  /// Provider-shape-aware extraction of tool_call ids from a raw assistant
  /// message. Knowing the shape per provider is the price of catching pairing
  /// bugs at request-construction time instead of at the 400 response.
  Iterable<String> _extractToolCallIds({
    required ChatTurnProviderStyle apiStyle,
    required Map<String, dynamic> rawJson,
  }) {
    switch (apiStyle) {
      case ChatTurnProviderStyle.openaiChatCompletions:
        final tcs = rawJson['tool_calls'];
        if (tcs is! List) return const [];
        return [
          for (final tc in tcs)
            if (tc is Map && tc['id'] is String) tc['id'] as String,
        ];

      case ChatTurnProviderStyle.anthropicMessages:
        final content = rawJson['content'];
        if (content is! List) return const [];
        return [
          for (final block in content)
            if (block is Map &&
                block['type'] == 'tool_use' &&
                block['id'] is String)
              block['id'] as String,
        ];

      case ChatTurnProviderStyle.openaiResponses:
        final outputs = rawJson['output'];
        if (outputs is! List) return const [];
        return [
          for (final item in outputs)
            if (item is Map &&
                item['type'] == 'function_call' &&
                item['call_id'] is String)
              item['call_id'] as String,
        ];
    }
  }
}
