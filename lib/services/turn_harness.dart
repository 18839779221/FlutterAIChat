import '../models/agent/chat_turn_step.dart';
import '../models/agent/model_tool_call.dart';
import '../models/agent/model_turn_decision.dart';
import '../models/agent/agent_loop_limits.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/interaction/ask_user_question_request.dart';
import '../models/interaction/ask_user_question_response.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_result.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../repositories/chat_turn_step_repository.dart';
import '../tools/core/tool_display_names.dart';
import '../utils/logger.dart';
import 'agent_planner_service.dart';
import 'chat_service.dart';
import 'turn_verifier.dart';
import 'turn_ledger_builder_service.dart';
import 'tool_call_service.dart';
import 'transcript_builder_service.dart';

class TurnHarness {
  static const _tag = 'TurnHarness';
  final AgentPlannerService _plannerService;
  final ChatTurnRepository _turnRepository;
  final ChatTurnStepRepository? _stepRepository;
  final ChatEventRepository _eventRepository;
  final TranscriptBuilderService _transcriptBuilderService;
  final TurnLedgerBuilderService _turnLedgerBuilder;
  final TurnVerifier _turnVerifier;
  final ChatService _chatService;
  final ToolCallService _toolCallService;
  final AgentLoopLimits _limits;

  TurnHarness({
    required AgentPlannerService plannerService,
    required ChatTurnRepository turnRepository,
    ChatTurnStepRepository? turnStepRepository,
    required ChatEventRepository eventRepository,
    required TranscriptBuilderService transcriptBuilderService,
    TurnLedgerBuilderService turnLedgerBuilder =
        const TurnLedgerBuilderService(),
    required TurnVerifier turnVerifier,
    required ChatService chatService,
    required ToolCallService toolCallService,
    AgentLoopLimits limits = const AgentLoopLimits(),
  })  : _plannerService = plannerService,
        _turnRepository = turnRepository,
        _stepRepository = turnStepRepository,
        _eventRepository = eventRepository,
        _transcriptBuilderService = transcriptBuilderService,
        _turnLedgerBuilder = turnLedgerBuilder,
        _turnVerifier = turnVerifier,
        _chatService = chatService,
        _toolCallService = toolCallService,
        _limits = limits;

  Stream<ChatEvent> runTurn({
    required ChatTurn turn,
    required ChatConfig config,
  }) async* {
    final turnId = turn.id!;
    Logger.i(
      _tag,
      'runTurn start turnId=$turnId groupId=${turn.groupId} iteration=${turn.iterationCount} toolCalls=${turn.toolCallCount} userInput=${_preview(turn.userInput)}',
    );
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
    await _turnRepository.markRunning(turnId);
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
      stepId: invocation.stepId,
    );
  }

  Stream<ChatEvent> resumeAfterQuestionAnswered({
    required int turnId,
    required AskUserQuestionRequest request,
    required AskUserQuestionResponse response,
    required ChatConfig config,
  }) async* {
    final currentTurn = await _requireTurn(turnId);
    await _turnRepository.markRunning(turnId);
    yield await _appendAndLoad(
      turnId,
      () => _eventRepository.appendUserInteractionResult(
        turnId: turnId,
        groupId: currentTurn.groupId,
        response: response,
        content: _formatUserInteractionTranscript(request, response),
      ),
    );
    if (request.stepId != null) {
      await _stepRepository?.markCompleted(
        request.stepId!,
        resultSummary: 'user_answered',
        resultJson: response.toJson(),
      );
    }

    final resumedTurn = await _turnRepository.getTurn(turnId) ?? currentTurn;
    yield* _continueTurnLoop(
      turn: resumedTurn,
      config: config,
      consecutiveFailures: 0,
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
      Logger.d(
        _tag,
        'transcript summary turnId=$turnId ${_summarizeTranscript(transcript)}',
      );
      final steps = _stepRepository == null
          ? <ChatTurnStep>[]
          : await _stepRepository!.listSteps(turnId);
      final decision = await _plannerService.planNextDecision(
            turn: currentTurn,
            transcript: transcript,
            steps: steps,
            config: config,
            limits: _limits,
          ) ??
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
            diagnosticCode: 'planner_request_failed',
            providerState: {},
            isTerminal: true,
          );
      await _persistDecisionRuntimeState(
        turnId: turnId,
        turn: currentTurn,
        decision: decision,
      );
      final runtimeTurn = await _turnRepository.getTurn(turnId) ?? currentTurn;
      final decisionResponseId = _resolveDecisionResponseId(decision);
      if (decision.toolCalls.isNotEmpty) {
        await _turnRepository.incrementIteration(turnId);
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendTurnStatus(
            turnId: turnId,
            groupId: runtimeTurn.groupId,
            content: _decisionStatusContent(decision),
          ),
        );

        var shouldBreakBatch = false;
        for (final toolCall in decision.toolCalls) {
          final stepId = _stepRepository == null
              ? null
              : await _stepRepository!.createStep(
                  ChatTurnStep(
                    turnId: turnId,
                    stepIndex: steps.length + 1,
                    providerResponseId: decisionResponseId,
                    providerCallId: toolCall.providerCallId,
                    toolName: toolCall.toolName,
                    toolArgsJson: toolCall.arguments,
                    status: ChatTurnStepStatus.planned,
                  ),
                );
          if (stepId != null) {
            steps.add(
              ChatTurnStep(
                id: stepId,
                turnId: turnId,
                stepIndex: steps.length + 1,
                providerResponseId: decisionResponseId,
                providerCallId: toolCall.providerCallId,
                toolName: toolCall.toolName,
                toolArgsJson: toolCall.arguments,
                status: ChatTurnStepStatus.planned,
              ),
            );
          }

          await for (final event in _executePlannedToolCall(
            turn: runtimeTurn,
            toolCall: toolCall,
            stepId: stepId,
            consecutiveFailures: failures,
            config: config,
          )) {
            yield event;
          }

          final refreshedTurn =
              await _turnRepository.getTurn(turnId) ?? currentTurn;
          if (refreshedTurn.status == ChatTurnStatus.awaitingToolConfirmation ||
              refreshedTurn.status == ChatTurnStatus.awaitingUserInteraction ||
              refreshedTurn.status == ChatTurnStatus.failed ||
              refreshedTurn.status == ChatTurnStatus.completed ||
              refreshedTurn.status == ChatTurnStatus.cancelled) {
            shouldBreakBatch = true;
            break;
          }

          if (stepId != null) {
            final persistedStep = await _stepRepository!.getStep(stepId);
            if (persistedStep == null ||
                persistedStep.status != ChatTurnStepStatus.completed) {
              shouldBreakBatch = true;
              break;
            }
          }
        }

        if (shouldBreakBatch) {
          break;
        }

        failures = 0;
        continue;
      }

      if (decision.isTerminal &&
          (decision.assistantMessage ?? '').trim().isNotEmpty) {
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendTurnStatus(
            turnId: turnId,
            groupId: runtimeTurn.groupId,
            content: _decisionStatusContent(decision),
          ),
        );
        Logger.i(
          _tag,
          'planner chose final response path for turnId=$turnId responsePreview=${_preview(decision.assistantMessage ?? '')}',
        );

        final answerTranscript =
            await _transcriptBuilderService.loadTranscript(turnId);
        Logger.d(
          _tag,
          'building final answer with transcriptEvents=${answerTranscript.length}',
        );
        final answerMessages =
            await _transcriptBuilderService.buildFinalAnswerMessages(
          groupId: runtimeTurn.groupId,
          turn: runtimeTurn,
          transcript: answerTranscript,
          systemPrompt: config.systemPrompt,
        );
        final finalSummary = _turnLedgerBuilder.buildFinalAnswerSummary(
          turn: runtimeTurn,
          steps: _stepRepository == null
              ? const []
              : await _stepRepository!.listSteps(turnId),
        );
        answerMessages.insert(
          config.systemPrompt.trim().isEmpty ? 0 : 1,
          ChatMessage(
            text: finalSummary,
            role: MessageRole.system,
            status: MessageStatus.completed,
          ),
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
              groupId: runtimeTurn.groupId,
              content: chunk,
            ),
          );
        }

        final finalText = buffer.toString();
        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendAssistantTextFinal(
            turnId: turnId,
            groupId: runtimeTurn.groupId,
            content: finalText,
          ),
        );

        final verifyResult = await _turnVerifier.verifyCanStop(
          turn: runtimeTurn,
          transcript: await _transcriptBuilderService.loadTranscript(turnId),
          steps: _stepRepository == null
              ? const []
              : await _stepRepository!.listSteps(turnId),
          latestAssistantText: finalText,
          limits: _limits,
        );

        if (verifyResult.canStop) {
          yield await _appendAndLoad(
            turnId,
            () => _eventRepository.appendFinalAnswer(
              turnId: turnId,
              groupId: runtimeTurn.groupId,
              content: finalText,
            ),
          );
          await _turnRepository.markCompleted(
            turnId,
            stopReason: verifyResult.reason,
            finalResponseText: finalText,
          );
          break;
        }

        yield await _appendAndLoad(
          turnId,
          () => _eventRepository.appendTurnStatus(
            turnId: turnId,
            groupId: runtimeTurn.groupId,
            content: verifyResult.reason,
          ),
        );
        Logger.w(
          _tag,
          'stop verifier requested another iteration for turnId=$turnId reason=${verifyResult.reason}',
        );
        await _turnRepository.incrementIteration(turnId);
        continue;
      }

      await _turnRepository.markFailed(
        turnId,
        errorMessage: 'planner_no_terminal_decision',
      );
      yield await _appendAndLoad(
        turnId,
        () => _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          content: 'planner_no_terminal_decision',
        ),
      );
      break;
    }
  }

  Future<void> _persistDecisionRuntimeState({
    required int turnId,
    required ChatTurn turn,
    required ModelTurnDecision decision,
  }) async {
    final nextProviderStyle = decision.providerStyle;
    final nextModelName = decision.modelName;
    final nextProviderState =
        decision.providerState.isEmpty ? null : decision.providerState;
    final hasChanges = nextProviderStyle != null ||
        nextModelName != null ||
        nextProviderState != null;
    if (!hasChanges) {
      return;
    }
    await _turnRepository.updateRuntimeState(
      turnId,
      providerStyle: nextProviderStyle ?? turn.providerStyle,
      modelName: nextModelName ?? turn.modelName,
      providerStateJson: nextProviderState ?? turn.providerStateJson,
    );
  }

  String? _resolveDecisionResponseId(ModelTurnDecision decision) {
    final responseId = decision.providerState['response_id'];
    if (responseId is! String) {
      return null;
    }
    final trimmed = responseId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Stream<ChatEvent> _executePlannedToolCall({
    required ChatTurn turn,
    required ModelToolCall toolCall,
    required int? stepId,
    required int consecutiveFailures,
    required ChatConfig config,
  }) async* {
    final toolDisplayName = resolveToolDisplayName(toolCall.toolName);
    Logger.d(
      _tag,
      'planner chose tool ${toolCall.toolName} with args=${toolCall.arguments}',
    );
    yield await _appendAndLoad(
      turn.id!,
      () => _eventRepository.appendToolCall(
        turnId: turn.id!,
        groupId: turn.groupId,
        toolName: toolCall.toolName,
        arguments: toolCall.arguments,
        summary: '准备执行工具：$toolDisplayName',
        payloadJson: {
          'toolName': toolCall.toolName,
          'arguments': toolCall.arguments,
          'providerCallId': toolCall.providerCallId,
          'status': ToolInvocationStatus.proposed.name,
          'summary': '准备执行工具：$toolDisplayName',
          'requiresConfirmation': false,
          'stepId': stepId,
        },
      ),
    );

    final definition = _toolCallService.findDefinition(toolCall.toolName);
    if (definition?.resolvedRuntimeKind == ToolRuntimeKind.userInteraction) {
      final request = AskUserQuestionRequest.fromJson({
        ...toolCall.arguments,
        'agentTurnId': turn.id!,
        if (stepId != null) 'stepId': stepId,
        if ((toolCall.providerCallId ?? '').trim().isNotEmpty)
          'providerCallId': toolCall.providerCallId,
      });
      await _turnRepository.markAwaitingUserInteraction(turn.id!);
      yield await _appendAndLoad(
        turn.id!,
        () => _eventRepository.appendAssistantQuestionPrompt(
          turnId: turn.id!,
          groupId: turn.groupId,
          request: request,
          content: _buildQuestionPromptSummary(request),
        ),
      );
      return;
    }

    final invocation = ToolInvocation(
      toolName: toolCall.toolName,
      arguments: toolCall.arguments,
      status: ToolInvocationStatus.running,
      summary: '正在执行工具：$toolDisplayName',
      requiresConfirmation: false,
      stepId: stepId,
    );
    final execution = await _toolCallService.executeToolInvocation(
      groupId: turn.groupId,
      invocation: invocation,
    );

    await for (final event in _handleToolExecution(
      turn: turn,
      invocation: invocation,
      execution: execution,
      consecutiveFailures: consecutiveFailures,
      config: config,
      resumeLoopAfterSuccess: false,
      stepId: stepId,
    )) {
      yield event;
    }
  }

  Stream<ChatEvent> _handleToolExecution({
    required ChatTurn turn,
    required ToolInvocation invocation,
    required ToolPreparationResult execution,
    required int consecutiveFailures,
    required ChatConfig config,
    bool resumeLoopAfterSuccess = true,
    int? stepId,
  }) async* {
    final turnId = turn.id!;
    final groupId = turn.groupId;
    final toolInvocation = execution.toolInvocation;
    final toolPayload = _buildToolInvocationPayload(
      invocation: toolInvocation ?? invocation,
      toolAccess: execution.toolAccess,
    );

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
          payloadJson: toolPayload,
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
        payloadJson: toolPayload,
      ),
    );
    if (stepId != null) {
      await _stepRepository?.markRunning(stepId);
    }

    final toolResult = execution.toolResult;
    if (toolResult == null ||
        toolResult.status == ToolExecutionStatus.failure) {
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
      await _turnRepository.incrementToolCallCount(turnId);
      if (stepId != null) {
        await _stepRepository?.markFailed(
          stepId,
          errorCode: toolResult?.errorMessage ?? 'tool_execution_failed',
          resultSummary: toolResult?.summary,
          resultJson: toolResult?.data,
        );
      }

      if (consecutiveFailures + 1 >= _limits.maxConsecutiveFailures) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: toolResult?.errorMessage ?? 'tool_execution_failed',
        );
        return;
      }
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
        content: _buildToolResultTranscriptContent(execution),
        payloadJson: toolResult.toJson(),
      ),
    );
    await _turnRepository.incrementToolCallCount(turnId);
    if (stepId != null) {
      await _stepRepository?.markCompleted(
        stepId,
        resultSummary: toolResult.summary,
        resultJson: toolResult.data,
      );
    }

    if (resumeLoopAfterSuccess) {
      final resumedTurn = await _turnRepository.getTurn(turnId) ?? turn;
      yield* _continueTurnLoop(
        turn: resumedTurn,
        config: config,
        consecutiveFailures: 0,
      );
    }
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

  String _summarizeTranscript(List<ChatEvent> transcript) {
    if (transcript.isEmpty) {
      return 'events=0';
    }

    final counts = <String, int>{};
    for (final event in transcript) {
      counts.update(
        event.eventType.name,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final parts =
        counts.entries.map((entry) => '${entry.key}:${entry.value}').join(', ');
    return 'events=${transcript.length} [$parts]';
  }

  String _preview(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '<empty>';
    }
    if (normalized.length <= 160) {
      return normalized;
    }
    return '${normalized.substring(0, 160)}...';
  }

  String _decisionStatusContent(ModelTurnDecision decision) {
    final code = decision.diagnosticCode?.trim();
    if (decision.toolCalls.isNotEmpty) {
      if (code == 'planner_action_call_tool' &&
          decision.toolCalls.length == 1) {
        return '$code:${decision.toolCalls.first.toolName}';
      }
      if (code != null &&
          code.isNotEmpty &&
          code != 'planner_action_call_tools') {
        return code;
      }
      return 'planner_action_call_tools:${decision.toolCalls.map((call) => call.toolName).join(',')}';
    }
    if (code != null && code.isNotEmpty) {
      return code;
    }
    return 'planner_action_respond';
  }

  String _buildToolResultTranscriptContent(ToolPreparationResult execution) {
    final toolResult = execution.toolResult;
    if (toolResult == null) {
      return '';
    }
    return toolResult.summary;
  }

  Map<String, dynamic> _buildToolInvocationPayload({
    required ToolInvocation invocation,
    required ToolAccessSnapshot? toolAccess,
  }) {
    return {
      ...invocation.toJson(),
      if (toolAccess != null) 'toolAccess': toolAccess.toJson(),
    };
  }

  String _buildQuestionPromptSummary(AskUserQuestionRequest request) {
    if (request.questions.length == 1) {
      return request.questions.single.question;
    }
    return '请先回答这 ${request.questions.length} 个问题';
  }

  String _formatUserInteractionTranscript(
    AskUserQuestionRequest request,
    AskUserQuestionResponse response,
  ) {
    final lines = <String>['User answered AskUserQuestion:'];
    for (final question in request.questions) {
      final answer = response.answersByQuestionId[question.id];
      if (answer == null || answer.trim().isEmpty) {
        continue;
      }
      final title = question.header.trim().isEmpty ? question.id : question.header;
      lines.add('- $title: ${answer.trim()}');
    }
    return lines.join('\n');
  }
}
