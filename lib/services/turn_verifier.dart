import '../models/agent/agent_loop_limits.dart';
import '../models/agent/chat_turn_step.dart';
import '../models/agent/stop_verification_result.dart';
import '../models/chat_event.dart';
import '../models/chat_turn.dart';

class TurnVerifier {
  Future<StopVerificationResult> verifyCanStop({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    List<ChatTurnStep> steps = const [],
    required String latestAssistantText,
    required AgentLoopLimits limits,
  }) async {
    if (turn.status == ChatTurnStatus.maxIterationsReached) {
      return const StopVerificationResult(
        canStop: true,
        reason: 'max_iterations_reached',
      );
    }

    if (turn.status == ChatTurnStatus.cancelled) {
      return const StopVerificationResult(
        canStop: true,
        reason: 'cancelled',
      );
    }

    if (turn.status == ChatTurnStatus.completed) {
      return const StopVerificationResult(
        canStop: true,
        reason: 'already_completed',
      );
    }

    if (turn.status == ChatTurnStatus.failed) {
      return const StopVerificationResult(
        canStop: true,
        reason: 'already_failed',
      );
    }

    if (turn.status == ChatTurnStatus.awaitingToolConfirmation) {
      return const StopVerificationResult(
        canStop: false,
        reason: 'awaiting_tool_confirmation',
      );
    }

    if (_hasPendingSteps(steps)) {
      return const StopVerificationResult(
        canStop: false,
        reason: 'unfinished_turn_steps',
      );
    }

    final latestToolLifecycleEvent = _findLatestToolLifecycleEvent(transcript);
    if (latestToolLifecycleEvent?.eventType ==
        ChatEventType.assistantToolConfirmation) {
      return const StopVerificationResult(
        canStop: false,
        reason: 'awaiting_tool_confirmation',
      );
    }

    if (latestToolLifecycleEvent?.eventType == ChatEventType.assistantToolCall ||
        latestToolLifecycleEvent?.eventType ==
            ChatEventType.toolExecutionStarted) {
      return const StopVerificationResult(
        canStop: false,
        reason: 'unfinished_tool_execution',
      );
    }

    if (latestAssistantText.trim().isEmpty) {
      return const StopVerificationResult(
        canStop: false,
        reason: 'empty_final_text',
      );
    }

    return const StopVerificationResult(
      canStop: true,
      reason: 'final_answer_ready',
    );
  }

  bool _hasPendingSteps(List<ChatTurnStep> steps) {
    return steps.any(
      (step) =>
          step.status == ChatTurnStepStatus.planned ||
          step.status == ChatTurnStepStatus.running,
    );
  }

  ChatEvent? _findLatestToolLifecycleEvent(List<ChatEvent> transcript) {
    for (final event in transcript.reversed) {
      switch (event.eventType) {
        case ChatEventType.assistantToolCall:
        case ChatEventType.assistantToolConfirmation:
        case ChatEventType.toolExecutionStarted:
        case ChatEventType.toolResult:
        case ChatEventType.toolError:
          return event;
        case ChatEventType.userMessage:
        case ChatEventType.assistantReasoningDelta:
        case ChatEventType.assistantTextDelta:
        case ChatEventType.assistantTextFinal:
        case ChatEventType.turnStatus:
        case ChatEventType.finalAnswer:
        case ChatEventType.error:
          continue;
      }
    }
    return null;
  }
}

@Deprecated('Use TurnVerifier instead.')
class StopVerifierService extends TurnVerifier {}
