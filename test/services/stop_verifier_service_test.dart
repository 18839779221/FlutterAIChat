import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/services/stop_verifier_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StopVerifierService', () {
    test('blocks stop when final text is empty', () async {
      final service = StopVerifierService();

      final result = await service.verifyCanStop(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: 'hello',
        ),
        transcript: const [],
        latestAssistantText: '   ',
        limits: const AgentLoopLimits(),
      );

      expect(result.canStop, isFalse);
      expect(result.reason, contains('empty'));
    });

    test('forces stop when turn already hit max iterations status', () async {
      final service = StopVerifierService();

      final result = await service.verifyCanStop(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.maxIterationsReached,
          userInput: 'hello',
        ),
        transcript: const <ChatEvent>[],
        latestAssistantText: 'done',
        limits: const AgentLoopLimits(),
      );

      expect(result.canStop, isTrue);
      expect(result.reason, contains('max_iterations'));
    });
  });
}
