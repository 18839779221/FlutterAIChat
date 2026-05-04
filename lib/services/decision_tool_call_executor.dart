import 'dart:async';
import 'dart:collection';

import '../models/agent/agent_loop_limits.dart';
import '../models/agent/chat_turn_step.dart';
import '../models/agent/model_tool_call.dart';
import '../models/agent/model_turn_decision.dart';
import '../models/chat_event.dart';
import '../models/chat_turn.dart';
import '../models/interaction/ask_user_question_request.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_result.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../repositories/chat_turn_step_repository.dart';
import '../services/chat_service.dart';
import '../tools/core/tool_display_names.dart';
import '../utils/logger.dart';
import 'tool_call_service.dart';

class DecisionToolExecutionSummary {
  final bool enteredAwaitingConfirmation;
  final bool enteredAwaitingUserInteraction;
  final bool hasFailedStep;
  final bool shouldStopFurtherExecution;
  final int executedToolCount;

  const DecisionToolExecutionSummary({
    this.enteredAwaitingConfirmation = false,
    this.enteredAwaitingUserInteraction = false,
    this.hasFailedStep = false,
    this.shouldStopFurtherExecution = false,
    this.executedToolCount = 0,
  });
}

class DecisionToolExecutionUpdate {
  final ChatEvent? event;
  final DecisionToolExecutionSummary? summary;

  const DecisionToolExecutionUpdate._({
    this.event,
    this.summary,
  });

  const DecisionToolExecutionUpdate.event(ChatEvent event)
      : this._(event: event);

  const DecisionToolExecutionUpdate.summary(
    DecisionToolExecutionSummary summary,
  ) : this._(summary: summary);
}

class DecisionToolExecutionBatch {
  final List<ModelToolCall> toolCalls;
  final bool isConcurrent;

  const DecisionToolExecutionBatch({
    required this.toolCalls,
    required this.isConcurrent,
  });
}

abstract class DecisionToolCallExecutor {
  Stream<DecisionToolExecutionUpdate> executeDecisionToolCalls({
    required ChatTurn turn,
    required ModelTurnDecision decision,
    required ChatConfig config,
    required int consecutiveFailures,
    int? sharedStepId,
  });
}

class DefaultDecisionToolCallExecutor implements DecisionToolCallExecutor {
  static const _tag = 'DecisionToolCallExecutor';
  static const int _defaultMaxConcurrentExecutions = 10;

  final ChatTurnRepository _turnRepository;
  final ChatTurnStepRepository? _stepRepository;
  final ChatEventRepository _eventRepository;
  final ToolCallService _toolCallService;
  final AgentLoopLimits _limits;
  final int _maxConcurrentExecutions;

  DefaultDecisionToolCallExecutor({
    required ChatTurnRepository turnRepository,
    required ChatEventRepository eventRepository,
    required ToolCallService toolCallService,
    required AgentLoopLimits limits,
    ChatTurnStepRepository? stepRepository,
    int maxConcurrentExecutions = _defaultMaxConcurrentExecutions,
  })  : _turnRepository = turnRepository,
        _eventRepository = eventRepository,
        _toolCallService = toolCallService,
        _limits = limits,
        _stepRepository = stepRepository,
        _maxConcurrentExecutions = maxConcurrentExecutions;

  @override
  Stream<DecisionToolExecutionUpdate> executeDecisionToolCalls({
    required ChatTurn turn,
    required ModelTurnDecision decision,
    required ChatConfig config,
    required int consecutiveFailures,
    int? sharedStepId,
  }) async* {
    final decisionResponseId = _resolveDecisionResponseId(decision);
    var executedToolCount = 0;
    var enteredAwaitingConfirmation = false;
    var enteredAwaitingUserInteraction = false;
    var hasFailedStep = false;
    var shouldStopFurtherExecution = false;

    for (final batch in debugBuildExecutionBatches(decision.toolCalls)) {
      final preparedCalls = await _createPreparedToolCalls(
        turnId: turn.id!,
        toolCalls: batch.toolCalls,
        sharedStepId: sharedStepId,
        decisionResponseId: decisionResponseId,
      );

      if (batch.isConcurrent) {
        var batchHasFailedStep = false;
        var batchEnteredAwaitingConfirmation = false;
        var batchEnteredAwaitingUserInteraction = false;
        await for (final update in _executeConcurrentBatch(
          turn: turn,
          preparedCalls: preparedCalls,
          consecutiveFailures: consecutiveFailures,
          config: config,
        )) {
          final event = update.event;
          if (event != null) {
            switch (event.eventType) {
              case ChatEventType.toolError:
                batchHasFailedStep = true;
                break;
              case ChatEventType.assistantToolConfirmation:
                batchEnteredAwaitingConfirmation = true;
                break;
              case ChatEventType.assistantQuestionPrompt:
                batchEnteredAwaitingUserInteraction = true;
                break;
              default:
                break;
            }
          }
          yield update;
        }
        executedToolCount += preparedCalls.length;
        final batchSummary = await _summarizeBatchOutcome(
          turn: turn,
          stepIds: preparedCalls.map((call) => call.stepId).toList(),
          hasFailedStepHint: batchHasFailedStep,
          enteredAwaitingConfirmationHint: batchEnteredAwaitingConfirmation,
          enteredAwaitingUserInteractionHint:
              batchEnteredAwaitingUserInteraction,
        );
        enteredAwaitingConfirmation = enteredAwaitingConfirmation ||
            batchSummary.enteredAwaitingConfirmation;
        enteredAwaitingUserInteraction = enteredAwaitingUserInteraction ||
            batchSummary.enteredAwaitingUserInteraction;
        hasFailedStep = hasFailedStep || batchSummary.hasFailedStep;
        shouldStopFurtherExecution =
            batchSummary.shouldStopFurtherExecution;
      } else {
        for (final preparedCall in preparedCalls) {
          var batchHasFailedStep = false;
          var batchEnteredAwaitingConfirmation = false;
          var batchEnteredAwaitingUserInteraction = false;
          await for (final event in _executePlannedToolCall(
            turn: turn,
            toolCall: preparedCall.toolCall,
            stepId: preparedCall.stepId,
            consecutiveFailures: consecutiveFailures,
            config: config,
            providerResponseId: preparedCall.providerResponseId,
          )) {
            switch (event.eventType) {
              case ChatEventType.toolError:
                batchHasFailedStep = true;
                break;
              case ChatEventType.assistantToolConfirmation:
                batchEnteredAwaitingConfirmation = true;
                break;
              case ChatEventType.assistantQuestionPrompt:
                batchEnteredAwaitingUserInteraction = true;
                break;
              default:
                break;
            }
            yield DecisionToolExecutionUpdate.event(event);
          }

          executedToolCount += 1;
          final executionSummary = await _summarizeBatchOutcome(
            turn: turn,
            stepIds: [preparedCall.stepId],
            hasFailedStepHint: batchHasFailedStep,
            enteredAwaitingConfirmationHint:
                batchEnteredAwaitingConfirmation,
            enteredAwaitingUserInteractionHint:
                batchEnteredAwaitingUserInteraction,
          );
          enteredAwaitingConfirmation = enteredAwaitingConfirmation ||
              executionSummary.enteredAwaitingConfirmation;
          enteredAwaitingUserInteraction = enteredAwaitingUserInteraction ||
              executionSummary.enteredAwaitingUserInteraction;
          hasFailedStep = hasFailedStep || executionSummary.hasFailedStep;
          shouldStopFurtherExecution =
              executionSummary.shouldStopFurtherExecution;
          if (shouldStopFurtherExecution) {
            break;
          }
        }
      }
      if (shouldStopFurtherExecution) {
        break;
      }
    }

    yield DecisionToolExecutionUpdate.summary(
      DecisionToolExecutionSummary(
        enteredAwaitingConfirmation: enteredAwaitingConfirmation,
        enteredAwaitingUserInteraction: enteredAwaitingUserInteraction,
        hasFailedStep: hasFailedStep,
        shouldStopFurtherExecution: shouldStopFurtherExecution,
        executedToolCount: executedToolCount,
      ),
    );
  }

  List<DecisionToolExecutionBatch> debugBuildExecutionBatches(
    List<ModelToolCall> toolCalls,
  ) {
    final batches = <DecisionToolExecutionBatch>[];
    var index = 0;
    while (index < toolCalls.length) {
      final current = toolCalls[index];
      final isConcurrent = _isConcurrencySafe(current.toolName);
      final batchCalls = <ModelToolCall>[current];
      index += 1;
      if (isConcurrent) {
        while (index < toolCalls.length &&
            _isConcurrencySafe(toolCalls[index].toolName)) {
          batchCalls.add(toolCalls[index]);
          index += 1;
        }
      }
      batches.add(
        DecisionToolExecutionBatch(
          toolCalls: batchCalls,
          isConcurrent: isConcurrent,
        ),
      );
    }
    return batches;
  }

  Future<List<_PreparedDecisionToolCall>> _createPreparedToolCalls({
    required int turnId,
    required List<ModelToolCall> toolCalls,
    required int? sharedStepId,
    required String? decisionResponseId,
  }) async {
    if (sharedStepId != null || _stepRepository == null) {
      return [
        for (final toolCall in toolCalls)
          _PreparedDecisionToolCall(
            toolCall: toolCall,
            stepId: sharedStepId,
            providerResponseId: decisionResponseId,
          ),
      ];
    }

    final preparedCalls = <_PreparedDecisionToolCall>[];
    var nextStepIndex =
        (await _stepRepository!.listSteps(turnId)).fold<int>(
              0,
              (maxValue, step) =>
                  step.stepIndex > maxValue ? step.stepIndex : maxValue,
            ) +
            1;
    for (final toolCall in toolCalls) {
      final stepId = await _stepRepository!.createStep(
        ChatTurnStep(
          turnId: turnId,
          stepIndex: nextStepIndex,
          providerResponseId: decisionResponseId,
          providerCallId: toolCall.providerCallId,
          toolName: toolCall.toolName,
          toolArgsJson: toolCall.arguments,
          status: ChatTurnStepStatus.planned,
        ),
      );
      nextStepIndex += 1;
      preparedCalls.add(
        _PreparedDecisionToolCall(
          toolCall: toolCall,
          stepId: stepId,
          providerResponseId: decisionResponseId,
        ),
      );
    }
    return preparedCalls;
  }

  Stream<DecisionToolExecutionUpdate> _executeConcurrentBatch({
    required ChatTurn turn,
    required List<_PreparedDecisionToolCall> preparedCalls,
    required int consecutiveFailures,
    required ChatConfig config,
  }) async* {
    if (preparedCalls.isEmpty) {
      return;
    }

    final controller = StreamController<DecisionToolExecutionUpdate>();
    final queue = ListQueue<_PreparedDecisionToolCall>.from(preparedCalls);
    Object? fatalError;
    StackTrace? fatalStackTrace;
    var activeCount = 0;

    Future<void> maybeClose() async {
      if (activeCount != 0 || queue.isNotEmpty || controller.isClosed) {
        return;
      }
      if (fatalError != null) {
        controller.addError(fatalError!, fatalStackTrace);
      }
      await controller.close();
    }

    void scheduleNext() {
      while (fatalError == null &&
          activeCount < _maxConcurrentExecutions &&
          queue.isNotEmpty) {
        final preparedCall = queue.removeFirst();
        activeCount += 1;
        unawaited(() async {
          try {
            await for (final event in _executePlannedToolCall(
              turn: turn,
              toolCall: preparedCall.toolCall,
              stepId: preparedCall.stepId,
              consecutiveFailures: consecutiveFailures,
              config: config,
              providerResponseId: preparedCall.providerResponseId,
            )) {
              controller.add(DecisionToolExecutionUpdate.event(event));
            }
          } catch (error, stackTrace) {
            fatalError ??= error;
            fatalStackTrace ??= stackTrace;
          } finally {
            activeCount -= 1;
            if (fatalError == null) {
              scheduleNext();
            }
            await maybeClose();
          }
        }());
      }
      unawaited(maybeClose());
    }

    scheduleNext();
    yield* controller.stream;
  }

  Future<DecisionToolExecutionSummary> _summarizeBatchOutcome({
    required ChatTurn turn,
    required List<int?> stepIds,
    bool hasFailedStepHint = false,
    bool enteredAwaitingConfirmationHint = false,
    bool enteredAwaitingUserInteractionHint = false,
  }) async {
    final refreshedTurn = await _turnRepository.getTurn(turn.id!) ?? turn;
    final enteredAwaitingConfirmation =
        enteredAwaitingConfirmationHint ||
        refreshedTurn.status == ChatTurnStatus.awaitingToolConfirmation;
    final enteredAwaitingUserInteraction =
        enteredAwaitingUserInteractionHint ||
        refreshedTurn.status == ChatTurnStatus.awaitingUserInteraction;
    final terminalOrStopped = refreshedTurn.status == ChatTurnStatus.failed ||
        refreshedTurn.status == ChatTurnStatus.completed ||
        refreshedTurn.status == ChatTurnStatus.cancelled;

    var hasFailedStep = hasFailedStepHint;
    var hasPendingStep = false;
    if (_stepRepository != null) {
      for (final stepId in stepIds.whereType<int>()) {
        final persistedStep = await _stepRepository!.getStep(stepId);
        if (persistedStep == null ||
            persistedStep.status == ChatTurnStepStatus.planned ||
            persistedStep.status == ChatTurnStepStatus.running) {
          hasPendingStep = true;
          continue;
        }
        if (persistedStep.status == ChatTurnStepStatus.failed) {
          hasFailedStep = true;
        }
      }
    }

    final shouldStop = enteredAwaitingConfirmation ||
        enteredAwaitingUserInteraction ||
        terminalOrStopped ||
        hasFailedStep ||
        hasPendingStep;

    return DecisionToolExecutionSummary(
      enteredAwaitingConfirmation: enteredAwaitingConfirmation,
      enteredAwaitingUserInteraction: enteredAwaitingUserInteraction,
      hasFailedStep: hasFailedStep,
      shouldStopFurtherExecution: shouldStop,
    );
  }

  bool _isConcurrencySafe(String toolName) {
    final definition = _toolCallService.findDefinition(toolName);
    return definition?.isConcurrencySafe ?? false;
  }

  String? _resolveDecisionResponseId(ModelTurnDecision decision) {
    final responseId = decision.providerState['response_id'] ??
        decision.providerState['message_id'];
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
    String? providerResponseId,
  }) async* {
    final toolDisplayName = resolveToolDisplayName(toolCall.toolName);
    Logger.trace(
      _tag,
      'tool.start',
      data: {
        'turnId': turn.id,
        'stepId': stepId,
        'toolName': toolCall.toolName,
      },
    );
    Logger.d(
      _tag,
      'planner chose tool ${toolCall.toolName} with args=${toolCall.arguments}',
    );
    yield await _eventRepository.appendToolCall(
      turnId: turn.id!,
      groupId: turn.groupId,
      toolName: toolCall.toolName,
      arguments: toolCall.arguments,
      summary: '准备执行工具：$toolDisplayName',
      payloadJson: {
        'toolName': toolCall.toolName,
        'arguments': toolCall.arguments,
        'providerCallId': toolCall.providerCallId,
        if (providerResponseId != null) 'providerResponseId': providerResponseId,
        'status': ToolInvocationStatus.proposed.name,
        'summary': '准备执行工具：$toolDisplayName',
        'requiresConfirmation': false,
        'stepId': stepId,
      },
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
      Logger.trace(
        _tag,
        'interaction.awaiting_user',
        data: {
          'turnId': turn.id,
          'stepId': stepId,
          'questionCount': request.questions.length,
        },
      );
      yield await _eventRepository.appendAssistantQuestionPrompt(
        turnId: turn.id!,
        groupId: turn.groupId,
        request: request,
        content: _buildQuestionPromptSummary(request),
        payloadJson: {
          ...request.toJson(),
          if (providerResponseId != null)
            'providerResponseId': providerResponseId,
        },
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
      providerCallId: toolCall.providerCallId,
    );
    final controller = StreamController<ChatEvent>();
    unawaited(() async {
      try {
        final execution = await _toolCallService.executeToolInvocation(
          groupId: turn.groupId,
          invocation: invocation,
          onExecutionStarted: ({required invocation, required toolAccess}) async {
            final toolPayload = _buildToolInvocationPayload(
              invocation: invocation,
              toolAccess: toolAccess,
            );
            controller.add(
              await _eventRepository.appendToolExecutionStarted(
                turnId: turn.id!,
                groupId: turn.groupId,
                content: invocation.summary,
                payloadJson: toolPayload,
              ),
            );
            if (stepId != null) {
              await _stepRepository?.markRunning(stepId);
            }
          },
        );

        await for (final event in _handleToolExecution(
          turn: turn,
          invocation: invocation,
          execution: execution,
          consecutiveFailures: consecutiveFailures,
          config: config,
          resumeLoopAfterSuccess: false,
          stepId: stepId,
          providerCallId: toolCall.providerCallId,
        )) {
          controller.add(event);
        }
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        await controller.close();
      }
    }());

    yield* controller.stream;
  }

  Stream<ChatEvent> _handleToolExecution({
    required ChatTurn turn,
    required ToolInvocation invocation,
    required ToolPreparationResult execution,
    required int consecutiveFailures,
    required ChatConfig config,
    bool resumeLoopAfterSuccess = true,
    int? stepId,
    String? providerCallId,
  }) async* {
    final turnId = turn.id!;
    final groupId = turn.groupId;
    final toolInvocation = _stableToolInvocation(
      fallback: invocation,
      override: execution.toolInvocation,
      stepId: stepId,
      providerCallId: providerCallId,
    );
    final toolPayload = _buildToolInvocationPayload(
      invocation: toolInvocation,
      toolAccess: execution.toolAccess,
    );

    if (toolInvocation.requiresConfirmation) {
      await _turnRepository.markAwaitingToolConfirmation(turnId);
      Logger.trace(
        _tag,
        'tool.awaiting_confirmation',
        data: {
          'turnId': turnId,
          'stepId': stepId,
          'toolName': toolInvocation.toolName,
        },
      );
      yield await _eventRepository.appendToolConfirmation(
        turnId: turnId,
        groupId: groupId,
        toolName: toolInvocation.toolName,
        arguments: toolInvocation.arguments,
        summary: toolInvocation.summary,
        payloadJson: toolPayload,
      );
      return;
    }

    if (!execution.executionStarted) {
      yield await _eventRepository.appendToolExecutionStarted(
        turnId: turnId,
        groupId: groupId,
        content: toolInvocation.summary,
        payloadJson: toolPayload,
      );
      if (stepId != null) {
        await _stepRepository?.markRunning(stepId);
      }
    }

    final toolResult = execution.toolResult;
    if (toolResult == null ||
        toolResult.status == ToolExecutionStatus.failure) {
      Logger.trace(
        _tag,
        'tool.failed',
        level: LogLevel.error,
        data: {
          'turnId': turnId,
          'stepId': stepId,
          'toolName': invocation.toolName,
          'error': toolResult?.errorMessage ?? 'tool_execution_failed',
        },
      );
      Logger.w(
        _tag,
        'tool execution failed for ${invocation.toolName}: ${toolResult?.errorMessage ?? 'tool_execution_failed'}',
      );
      yield await _eventRepository.appendToolError(
        turnId: turnId,
        groupId: groupId,
        content: toolResult?.summary ?? 'tool_execution_failed',
        errorCode: toolResult?.errorMessage,
        payloadJson: {
          ...?toolResult?.toJson(),
          if (providerCallId != null) 'providerCallId': providerCallId,
        },
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

      final maxConsecutiveFailures = _limits.maxConsecutiveFailures;
      if (maxConsecutiveFailures != null &&
          consecutiveFailures + 1 >= maxConsecutiveFailures) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: toolResult?.errorMessage ?? 'tool_execution_failed',
        );
      }
      return;
    }

    Logger.d(
      _tag,
      'tool execution succeeded for ${invocation.toolName}: ${toolResult.summary}',
    );
    Logger.trace(
      _tag,
      'tool.done',
      data: {
        'turnId': turnId,
        'stepId': stepId,
        'toolName': invocation.toolName,
      },
    );
    yield await _eventRepository.appendToolResult(
      turnId: turnId,
      groupId: groupId,
      content: toolResult.summary,
      payloadJson: {
        ...toolResult.toJson(),
        if (stepId != null) 'stepId': stepId,
        if (providerCallId != null) 'providerCallId': providerCallId,
      },
    );
    await _turnRepository.incrementToolCallCount(turnId);
    if (stepId != null) {
      await _stepRepository?.markCompleted(
        stepId,
        resultSummary: toolResult.summary,
        resultJson: toolResult.data,
      );
    }
  }

  ToolInvocation _stableToolInvocation({
    required ToolInvocation fallback,
    required ToolInvocation? override,
    required int? stepId,
    required String? providerCallId,
  }) {
    final effective = override ?? fallback;
    return effective.copyWith(
      stepId: stepId ?? effective.stepId,
      providerCallId: providerCallId ?? effective.providerCallId,
    );
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
}

class _PreparedDecisionToolCall {
  final ModelToolCall toolCall;
  final int? stepId;
  final String? providerResponseId;

  const _PreparedDecisionToolCall({
    required this.toolCall,
    required this.stepId,
    this.providerResponseId,
  });
}
