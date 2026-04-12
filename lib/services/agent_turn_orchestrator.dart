import '../models/agent/agent_action.dart';
import '../models/agent/agent_loop_limits.dart';
import '../models/chat_event.dart';
import '../models/chat_turn.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_result.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../utils/logger.dart';
import 'agent_planner_service.dart';
import 'chat_service.dart';
import 'stop_verifier_service.dart';
import 'tool_call_service.dart';
import 'transcript_builder_service.dart';

class AgentTurnOrchestrator {
  static const _tag = 'AgentTurnOrchestrator';
  final AgentPlannerService _plannerService;
  final ChatTurnRepository _turnRepository;
  final ChatEventRepository _eventRepository;
  final TranscriptBuilderService _transcriptBuilderService;
  final StopVerifierService _stopVerifierService;
  final ChatService _chatService;
  final ToolCallService _toolCallService;
  final AgentLoopLimits _limits;

  AgentTurnOrchestrator({
    required AgentPlannerService plannerService,
    required ChatTurnRepository turnRepository,
    required ChatEventRepository eventRepository,
    required TranscriptBuilderService transcriptBuilderService,
    required StopVerifierService stopVerifierService,
    required ChatService chatService,
    required ToolCallService toolCallService,
    AgentLoopLimits limits = const AgentLoopLimits(),
  })  : _plannerService = plannerService,
        _turnRepository = turnRepository,
        _eventRepository = eventRepository,
        _transcriptBuilderService = transcriptBuilderService,
        _stopVerifierService = stopVerifierService,
        _chatService = chatService,
        _toolCallService = toolCallService,
        _limits = limits;

  Stream<ChatEvent> runTurn({
    required ChatTurn turn,
    required ChatConfig config,
  }) async* {
    final turnId = turn.id!;
    yield await _appendAndLoad(
      turnId,
      () => _eventRepository.appendUserMessage(
        turnId: turnId,
        groupId: turn.groupId,
        content: turn.userInput,
      ),
    );

    yield* _continueTurnLoop(
      turn: turn,
      config: config,
      consecutiveFailures: 0,
    );
  }

  Stream<ChatEvent> resumeAfterConfirmation({
    required int turnId,
    required ToolInvocation invocation,
    required ChatConfig config,
    bool trustTool = false,
  }) async* {
    final currentTurn = await _requireTurn(turnId);
    final execution = await _toolCallService.executeToolInvocation(
      groupId: currentTurn.groupId,
      invocation: invocation,
      trustTool: trustTool,
    );

    yield* _handleToolExecution(
      turn: currentTurn,
      invocation: invocation,
      execution: execution,
      consecutiveFailures: 0,
      config: config,
    );
  }

  Stream<ChatEvent> _continueTurnLoop({
    required ChatTurn turn,
    required ChatConfig config,
    required int consecutiveFailures,
  }) async* {
    final turnId = turn.id!;
    var failures = consecutiveFailures;

    while (true) {
      final currentTurn = await _turnRepository.getTurn(turnId) ?? turn;
      if (currentTurn.iterationCount >= _limits.maxIterations) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: 'max_iterations_reached',
        );
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendTurnStatus(
            turnId: turnId,
            groupId: currentTurn.groupId,
            content: 'max_iterations_reached',
          ),
        );
        break;
      }

      final transcript = await _transcriptBuilderService.loadTranscript(turnId);
      Logger.d(
        _tag,
        'planning iteration=${currentTurn.iterationCount} toolCalls=${currentTurn.toolCallCount} transcriptEvents=${transcript.length}',
      );
      final action = await _plannerService.planNextAction(
        turn: currentTurn,
        transcript: transcript,
        config: config,
        limits: _limits,
      );

      if (action.type == AgentActionType.callTool && action.toolCall != null) {
        final toolCall = action.toolCall!;
        Logger.d(
          _tag,
          'planner chose tool ${toolCall.toolName} with args=${toolCall.arguments}',
        );
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendToolCall(
            turnId: turnId,
            groupId: currentTurn.groupId,
            toolName: toolCall.toolName,
            arguments: toolCall.arguments,
            summary: '准备执行工具：${toolCall.toolName}',
          ),
        );

        final invocation = ToolInvocation(
          toolName: toolCall.toolName,
          arguments: toolCall.arguments,
          status: ToolInvocationStatus.running,
          summary: '正在执行工具：${toolCall.toolName}',
          requiresConfirmation: false,
        );
        final execution = await _toolCallService.executeToolInvocation(
          groupId: currentTurn.groupId,
          invocation: invocation,
        );

        final executionEvents = _handleToolExecution(
          turn: currentTurn,
          invocation: invocation,
          execution: execution,
          consecutiveFailures: failures,
          config: config,
        );
        await for (final event in executionEvents) {
          yield event;
        }

        final refreshedTurn = await _turnRepository.getTurn(turnId) ?? currentTurn;
        if (refreshedTurn.status == ChatTurnStatus.awaitingToolConfirmation ||
            refreshedTurn.status == ChatTurnStatus.failed ||
            refreshedTurn.status == ChatTurnStatus.completed ||
            refreshedTurn.status == ChatTurnStatus.cancelled) {
          break;
        }
        failures = 0;
        continue;
      }

      Logger.d(_tag, 'planner chose final response path');

      final answerTranscript = await _transcriptBuilderService.loadTranscript(turnId);
      Logger.d(
        _tag,
        'building final answer with transcriptEvents=${answerTranscript.length}',
      );
      final answerMessages =
          await _transcriptBuilderService.buildFinalAnswerMessages(
        groupId: currentTurn.groupId,
        turn: currentTurn,
        transcript: answerTranscript,
        systemPrompt: config.systemPrompt,
      );

      final buffer = StringBuffer();
      await for (final chunk in _chatService.streamFinalAnswer(
        messages: answerMessages,
        config: config,
      )) {
        buffer.write(chunk);
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendAssistantTextDelta(
            turnId: turnId,
            groupId: currentTurn.groupId,
            content: chunk,
          ),
        );
      }

      final finalText = buffer.toString();
      yield await _appendAndLoad(
        turnId,
        () => _eventRepository.appendAssistantTextFinal(
          turnId: turnId,
          groupId: currentTurn.groupId,
          content: finalText,
        ),
      );

      final verifyResult = await _stopVerifierService.verifyCanStop(
        turn: currentTurn,
        transcript: await _transcriptBuilderService.loadTranscript(turnId),
        latestAssistantText: finalText,
        limits: _limits,
      );

      if (verifyResult.canStop) {
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendFinalAnswer(
            turnId: turnId,
            groupId: currentTurn.groupId,
            content: finalText,
          ),
        );
        await _turnRepository.markCompleted(
          turnId,
          stopReason: verifyResult.reason,
        );
        break;
      }

      yield await _appendAndLoad(
        turnId,
        () => _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: currentTurn.groupId,
          content: verifyResult.reason,
        ),
      );
      await _turnRepository.incrementIteration(turnId);
    }
  }

  Stream<ChatEvent> _handleToolExecution({
    required ChatTurn turn,
    required ToolInvocation invocation,
    required ToolPreparationResult execution,
    required int consecutiveFailures,
    required ChatConfig config,
  }) async* {
    final turnId = turn.id!;
    final groupId = turn.groupId;
    final toolInvocation = execution.toolInvocation;

    if (toolInvocation != null && toolInvocation.requiresConfirmation) {
      await _turnRepository.markAwaitingToolConfirmation(turnId);
      yield await _appendAndLoad(
        turnId,
        () => _eventRepository.appendToolConfirmation(
          turnId: turnId,
          groupId: groupId,
          toolName: toolInvocation.toolName,
          arguments: toolInvocation.arguments,
          summary: toolInvocation.summary,
        ),
      );
      return;
    }

    yield await _appendAndLoad(
      turnId,
      () => _eventRepository.appendToolExecutionStarted(
        turnId: turnId,
        groupId: groupId,
        content: toolInvocation?.summary ?? invocation.summary,
      ),
    );

    final toolResult = execution.toolResult;
    if (toolResult == null || toolResult.status == ToolExecutionStatus.failure) {
      Logger.w(
        _tag,
        'tool execution failed for ${invocation.toolName}: ${toolResult?.errorMessage ?? 'tool_execution_failed'}',
      );
      yield await _appendAndLoad(
        turnId,
        () => _eventRepository.appendToolError(
          turnId: turnId,
          groupId: groupId,
          content: toolResult?.summary ?? 'tool_execution_failed',
          errorCode: toolResult?.errorMessage,
        ),
      );

      if (consecutiveFailures + 1 >= _limits.maxConsecutiveFailures) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: toolResult?.errorMessage ?? 'tool_execution_failed',
        );
        return;
      }

      await _turnRepository.incrementIterationAndToolCount(turnId);
      return;
    }

    Logger.d(
      _tag,
      'tool execution succeeded for ${invocation.toolName}: ${toolResult.summary}',
    );
    yield await _appendAndLoad(
      turnId,
      () => _eventRepository.appendToolResult(
        turnId: turnId,
        groupId: groupId,
        content: toolResult.summary,
        payloadJson: toolResult.toJson(),
      ),
    );
    await _turnRepository.incrementIterationAndToolCount(turnId);

    final resumedTurn = await _turnRepository.getTurn(turnId) ?? turn;
    yield* _continueTurnLoop(
      turn: resumedTurn,
      config: config,
      consecutiveFailures: 0,
    );
  }

  Future<ChatTurn> _requireTurn(int turnId) async {
    final turn = await _turnRepository.getTurn(turnId);
    if (turn == null) {
      throw StateError('Turn $turnId not found');
    }
    return turn;
  }

  Future<ChatEvent> _appendAndLoad(
    int turnId,
    Future<int> Function() append,
  ) async {
    await append();
    final events = await _eventRepository.listEventsByTurn(turnId);
    return events.last;
  }
}
