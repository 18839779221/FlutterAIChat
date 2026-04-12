import '../models/agent/agent_loop_limits.dart';
import '../models/agent/stop_verification_result.dart';
import '../models/chat_event.dart';
import '../models/chat_turn.dart';

class StopVerifierService {
  Future<StopVerificationResult> verifyCanStop({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
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
}
