import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnVerifier', () {
    test('blocks stop when turn is awaiting tool confirmation', () async {
      final service = TurnVerifier();

      final result = await service.verifyCanStop(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.awaitingToolConfirmation,
          userInput: 'hello',
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolConfirmation,
            content: '等待用户确认',
            payloadJson: {
              'toolName': 'create_reminder',
              'status': 'awaitingConfirmation',
              'requiresConfirmation': true,
            },
          ),
        ],
        latestAssistantText: '我已经准备好了',
        limits: const AgentLoopLimits(),
      );

      expect(result.canStop, isFalse);
      expect(result.reason, 'awaiting_tool_confirmation');
    });

    test('blocks stop when transcript still has unfinished tool execution', () async {
      final service = TurnVerifier();

      final result = await service.verifyCanStop(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: 'hello',
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolCall,
            content: '准备执行工具',
            payloadJson: {
              'toolName': 'search_chat_history',
              'status': 'proposed',
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolExecutionStarted,
            content: '正在执行工具',
            payloadJson: {
              'toolName': 'search_chat_history',
              'status': 'running',
            },
          ),
        ],
        latestAssistantText: '这是一个候选答案',
        limits: const AgentLoopLimits(),
      );

      expect(result.canStop, isFalse);
      expect(result.reason, 'unfinished_tool_execution');
    });

    test('blocks stop when final text is empty', () async {
      final service = TurnVerifier();

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
      final service = TurnVerifier();

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

    test('blocks stop when step ledger still has pending work', () async {
      final service = TurnVerifier();

      final result = await service.verifyCanStop(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: 'hello',
        ),
        transcript: const [],
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 1,
            stepIndex: 1,
            toolName: 'search_chat_history',
            toolArgsJson: const {'query': '数据库'},
            status: ChatTurnStepStatus.running,
          ),
        ],
        latestAssistantText: '我觉得可以结束',
        limits: const AgentLoopLimits(),
      );

      expect(result.canStop, isFalse);
      expect(result.reason, 'unfinished_turn_steps');
    });

    test('allows stop when transcript work is fully closed and final text is ready',
        () async {
      final service = TurnVerifier();

      final result = await service.verifyCanStop(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: 'hello',
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolCall,
            content: '准备执行工具',
            payloadJson: {
              'toolName': 'search_chat_history',
              'status': 'proposed',
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolExecutionStarted,
            content: '正在执行工具',
            payloadJson: {
              'toolName': 'search_chat_history',
              'status': 'running',
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            content: '已找到结果',
            payloadJson: {
              'toolName': 'search_chat_history',
              'status': 'success',
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.assistantTextFinal,
            content: '这是最终答案草稿',
          ),
        ],
        latestAssistantText: '这是最终答案草稿',
        limits: const AgentLoopLimits(),
      );

      expect(result.canStop, isTrue);
      expect(result.reason, 'final_answer_ready');
    });
  });
}
