import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent/chat_turn_step.dart';
import '../models/agent/model_turn_decision.dart';
import '../models/agent/agent_loop_limits.dart';
import '../models/chat_event.dart';
import '../models/chat/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat/send_message_request.dart';
import '../models/chat_turn.dart';
import '../models/interaction/ask_user_question_request.dart';
import '../models/context/planner_context_carrier.dart';
import '../models/interaction/ask_user_question_response.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_result.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../repositories/chat_turn_step_repository.dart';
import '../storage/chat_storage.dart';
import '../utils/logger.dart';
import 'agent_planner_service.dart';
import 'chat_service.dart';
import 'decision_tool_call_executor.dart';
import 'follow_up_dispatch_queue.dart';
import 'turn_verifier.dart';
import 'tool_call_service.dart';
import 'transcript_builder_service.dart';
import 'session_context_projector.dart';
import 'session_context_service.dart';
import 'session_runtime_marker_service.dart';

class TurnHarness {
  static const _tag = 'TurnHarness';
  static const _seededUserMessagesRuntimeContextKey = 'seeded_user_messages';
  final AgentPlannerService _plannerService;
  final ChatTurnRepository _turnRepository;
  final ChatTurnStepRepository? _stepRepository;
  final ChatEventRepository _eventRepository;
  final TranscriptBuilderService _transcriptBuilderService;
  final TurnVerifier _turnVerifier;
  final ToolCallService _toolCallService;
  final DecisionToolCallExecutor _decisionToolCallExecutor;
  final AgentLoopLimits _limits;
  final SessionContextService? _sessionContextService;
  final ChatStorage _chatStorage;
  final FollowUpDispatchQueue? _followUpDispatchQueue;

  TurnHarness({
    required AgentPlannerService plannerService,
    required ChatTurnRepository turnRepository,
    ChatTurnStepRepository? turnStepRepository,
    required ChatEventRepository eventRepository,
    required TranscriptBuilderService transcriptBuilderService,
    required TurnVerifier turnVerifier,
    required ToolCallService toolCallService,
    required ChatStorage chatStorage,
    SessionContextService? sessionContextService,
    FollowUpDispatchQueue? followUpDispatchQueue,
    DecisionToolCallExecutor? decisionToolCallExecutor,
    AgentLoopLimits limits = const AgentLoopLimits(),
  })  : _plannerService = plannerService,
        _turnRepository = turnRepository,
        _stepRepository = turnStepRepository,
        _eventRepository = eventRepository,
        _transcriptBuilderService = transcriptBuilderService,
        _turnVerifier = turnVerifier,
        _toolCallService = toolCallService,
        _chatStorage = chatStorage,
        _decisionToolCallExecutor = decisionToolCallExecutor ??
            DefaultDecisionToolCallExecutor(
              turnRepository: turnRepository,
              stepRepository: turnStepRepository,
              eventRepository: eventRepository,
              toolCallService: toolCallService,
              limits: limits,
            ),
        _sessionContextService = sessionContextService,
        _followUpDispatchQueue = followUpDispatchQueue,
        _limits = limits;

  Stream<ChatEvent> runTurn({
    required ChatTurn turn,
    required ChatConfig config,
  }) async* {
    final turnId = turn.id!;
    Logger.trace(
      _tag,
      'turn.start',
      data: {
        'turnId': turnId,
        'groupId': turn.groupId,
        'iteration': turn.iterationCount,
        'toolCalls': turn.toolCallCount,
      },
    );
    Logger.i(
      _tag,
      'runTurn start turnId=$turnId groupId=${turn.groupId} iteration=${turn.iterationCount} toolCalls=${turn.toolCallCount} userInput=${_preview(turn.userInput)}',
    );
    final explicitSkillReminder = _extractExplicitSkillReminderMessage(turn);
    if (explicitSkillReminder != null) {
      yield await _eventRepository.appendUserMessage(
        turnId: turnId,
        groupId: turn.groupId,
        content: explicitSkillReminder.text,
        kind: ChatEventUserMessageKind.systemReminder,
      );
    }
    final seededUserMessages = _extractSeededUserMessages(turn);
    if (seededUserMessages.isNotEmpty) {
      for (final seed in seededUserMessages) {
        yield await _eventRepository.appendUserMessage(
          turnId: turnId,
          groupId: turn.groupId,
          content: seed.text,
          kind: seed.kind,
          attachments: seed.attachments,
        );
      }
    } else {
      final userAttachments = _extractUserAttachments(turn);
      yield await _eventRepository.appendUserMessage(
        turnId: turnId,
        groupId: turn.groupId,
        content: turn.userInput,
        attachments: userAttachments,
      );
    }

    yield* _continueTurnLoop(
      turn: turn,
      config: config,
      consecutiveFailures: 0,
    );
  }

  ChatMessage? _extractExplicitSkillReminderMessage(ChatTurn? turn) {
    final runtimeContext =
        turn?.providerStateJson?[SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return null;
    }
    final reminder = runtimeContext['explicit_skill_reminder'];
    if (reminder is! String || reminder.trim().isEmpty) {
      return null;
    }
    return ChatMessage(
      text: reminder,
      role: MessageRole.user,
      status: MessageStatus.completed,
    );
  }

  List<ChatAttachment> _extractUserAttachments(ChatTurn? turn) {
    final runtimeContext =
        turn?.providerStateJson?[SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return const <ChatAttachment>[];
    }
    final rawAttachments = runtimeContext['user_attachments'];
    if (rawAttachments is! List) {
      Logger.temp(
        _tag,
        'attachments.turn_runtime_context_missing',
        reason: 'diagnose_image_attachment_context_chain',
        data: {
          'turnId': turn?.id,
          'groupId': turn?.groupId,
          'runtimeContextKeys':
              runtimeContext.keys.map((key) => '$key').toList(),
        },
      );
      return const <ChatAttachment>[];
    }
    final attachments = rawAttachments
        .whereType<Map>()
        .map(
          (item) => ChatAttachment.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
    Logger.temp(
      _tag,
      'attachments.turn_runtime_context_extracted',
      reason: 'diagnose_image_attachment_context_chain',
      data: {
        'turnId': turn?.id,
        'groupId': turn?.groupId,
        'attachmentCount': attachments.length,
        'localIds':
            attachments.map((attachment) => attachment.localId).toList(),
        'hasProviderDataUrl': attachments
            .map(
              (attachment) =>
                  attachment.providerFileRefJson?['data_url'] is String &&
                  (attachment.providerFileRefJson?['data_url'] as String)
                      .trim()
                      .isNotEmpty,
            )
            .toList(),
      },
    );
    return attachments;
  }

  List<_TurnUserMessageSeed> _extractSeededUserMessages(ChatTurn? turn) {
    final runtimeContext =
        turn?.providerStateJson?[SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return const <_TurnUserMessageSeed>[];
    }
    final rawMessages = runtimeContext[_seededUserMessagesRuntimeContextKey];
    if (rawMessages is! List) {
      return const <_TurnUserMessageSeed>[];
    }
    return rawMessages
        .whereType<Map>()
        .map((item) => _TurnUserMessageSeed.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Stream<ChatEvent> resumeAfterConfirmation({
    required int turnId,
    required ToolInvocation invocation,
    required ChatConfig config,
    bool trustTool = false,
  }) async* {
    final currentTurn = await _requireTurn(turnId);
    Logger.trace(
      _tag,
      'interaction.resume_confirmation',
      data: {
        'turnId': turnId,
        'toolName': invocation.toolName,
        'stepId': invocation.stepId,
        'trustTool': trustTool,
      },
    );
    await _turnRepository.markRunning(turnId);
    final controller = StreamController<ChatEvent>();
    unawaited(() async {
      try {
        final execution = await _toolCallService.executeToolInvocation(
          groupId: currentTurn.groupId,
          invocation: invocation,
          trustTool: trustTool,
          currentTurnEvents: await _eventRepository.listEventsByTurn(turnId),
          sideRuntimeConfigOverride: config.sideRuntimeConfigOverride,
          onExecutionStarted: (
              {required invocation, required toolAccess}) async {
            final toolPayload = _buildToolInvocationPayload(
              invocation: invocation,
              toolAccess: toolAccess,
            );
            controller.add(
              await _eventRepository.appendToolExecutionStarted(
                turnId: turnId,
                groupId: currentTurn.groupId,
                content: invocation.summary,
                payloadJson: toolPayload,
              ),
            );
            if (invocation.stepId != null) {
              await _stepRepository?.markRunning(invocation.stepId!);
            }
          },
        );

        await for (final event in _handleToolExecution(
          turn: currentTurn,
          invocation: invocation,
          execution: execution,
          consecutiveFailures: 0,
          config: config,
          stepId: invocation.stepId,
        )) {
          controller.add(event);
        }

        final refreshedTurn =
            await _turnRepository.getTurn(turnId) ?? currentTurn;
        final failedToolExecution = execution.toolResult == null ||
            execution.toolResult!.status == ToolExecutionStatus.failure;
        if (failedToolExecution &&
            refreshedTurn.status == ChatTurnStatus.running) {
          await for (final event in _continueTurnLoop(
            turn: refreshedTurn,
            config: config,
            consecutiveFailures: 1,
          )) {
            controller.add(event);
          }
        }
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        await controller.close();
      }
    }());

    yield* controller.stream;
  }

  Stream<ChatEvent> resumeAfterQuestionAnswered({
    required int turnId,
    required AskUserQuestionRequest request,
    required AskUserQuestionResponse response,
    required ChatConfig config,
  }) async* {
    final currentTurn = await _requireTurn(turnId);
    Logger.trace(
      _tag,
      'interaction.resumed',
      data: {
        'turnId': turnId,
        'questionCount': request.questions.length,
        'stepId': request.stepId,
      },
    );
    await _turnRepository.markRunning(turnId);
    yield await _eventRepository.appendUserInteractionResult(
      turnId: turnId,
      groupId: currentTurn.groupId,
      response: response,
      content: _formatUserInteractionTranscript(request, response),
      payloadJson: {
        ...response.toJson(),
        if ((request.providerCallId ?? '').trim().isNotEmpty)
          'providerCallId': request.providerCallId,
      },
    );
    if (request.stepId != null) {
      final transcriptContent = _formatUserInteractionTranscript(
        request,
        response,
      );
      await _stepRepository?.markCompleted(
        request.stepId!,
        resultSummary: 'user_answered',
        resultJson: {
          ...response.toJson(),
          'transcriptContent': transcriptContent,
        },
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
      final maxToolCallsPerTurn = _limits.maxToolCallsPerTurn;
      if (maxToolCallsPerTurn != null &&
          currentTurn.toolCallCount >= maxToolCallsPerTurn) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: 'max_tool_calls_reached',
        );
        yield await _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: currentTurn.groupId,
          content: 'max_tool_calls_reached',
        );
        break;
      }
      final maxDuration = _limits.maxDuration;
      final elapsed = DateTime.now().difference(currentTurn.createdAt);
      if (maxDuration != null && elapsed >= maxDuration) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: 'max_duration_reached',
        );
        yield await _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: currentTurn.groupId,
          content: 'max_duration_reached',
        );
        break;
      }
      final maxIterations = _limits.maxIterations;
      if (maxIterations != null &&
          currentTurn.iterationCount >= maxIterations) {
        await _turnRepository.markFailed(
          turnId,
          errorMessage: 'max_iterations_reached',
        );
        yield await _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: currentTurn.groupId,
          content: 'max_iterations_reached',
        );
        break;
      }

      final insertedFollowUps =
          await _consumeSteerFollowUpsBeforePlanner(currentTurn);
      for (final event in insertedFollowUps) {
        yield event;
      }
      final transcript = await _transcriptBuilderService.loadTranscript(turnId);
      final compactionRestart = await _maybeAutoCompactAndRestart(
        turn: currentTurn,
        transcript: transcript,
        config: config,
      );
      if (compactionRestart != null) {
        if (compactionRestart.boundaryEvent != null) {
          yield compactionRestart.boundaryEvent!;
        }
        yield* _continueTurnLoop(
          turn: compactionRestart.continuationTurn,
          config: config,
          consecutiveFailures: failures,
        );
        break;
      }
      Logger.trace(
        _tag,
        'planner.start',
        data: {
          'turnId': turnId,
          'iteration': currentTurn.iterationCount,
          'toolCalls': currentTurn.toolCallCount,
          'transcriptEvents': transcript.length,
        },
      );
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
      final carriers = await _buildPlannerCarriers(
        groupId: currentTurn.groupId,
        currentTurnId: turnId,
        currentTurnTranscript: transcript,
        config: config,
      );
      final group = await _chatStorage.getGroupById(currentTurn.groupId);
      if (group == null) {
        throw StateError(
          'Group ${currentTurn.groupId} not found while planning turn $turnId',
        );
      }
      final decision = await _plannerService.planNextDecision(
            turn: currentTurn,
            transcript: transcript,
            steps: steps,
            config: config,
            limits: _limits,
            carriers: carriers,
            activeApiStyle: currentTurn.providerStyle ??
                ChatTurnProviderStyle.openaiChatCompletions,
            currentTurnRunning: true,
          ) ??
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
            diagnosticCode: 'planner_request_failed',
            providerState: {},
            isTerminal: true,
          );
      Logger.trace(
        _tag,
        'planner.done',
        data: {
          'turnId': turnId,
          'diagnosticCode': decision.diagnosticCode,
          'toolCalls': decision.toolCalls.length,
          'isTerminal': decision.isTerminal,
        },
      );
      await _persistDecisionRuntimeState(
        turnId: turnId,
        turn: currentTurn,
        decision: decision,
      );
      final runtimeTurn = await _turnRepository.getTurn(turnId) ?? currentTurn;
      // Persist the provider's raw assistant message for round-trip replay
      // (spec 2026-05-22). One event per planner iteration with content.
      final rawAssistantMessage =
          decision.providerState['raw_assistant_message'];
      if (rawAssistantMessage is Map<String, dynamic> &&
          decision.providerStyle != null) {
        yield await _eventRepository.appendAssistantTurnSnapshot(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          apiStyle: decision.providerStyle!,
          rawAssistantMessageJson: rawAssistantMessage,
        );
      }
      final plannerAssistantMessage = (decision.assistantMessage ?? '').trim();
      final shouldPersistPlannerMessage = plannerAssistantMessage.isNotEmpty &&
          !(decision.isTerminal && decision.toolCalls.isEmpty);
      if (shouldPersistPlannerMessage) {
        yield await _eventRepository.appendAssistantPlannerMessage(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          content: plannerAssistantMessage,
          payloadJson: {
            'diagnosticCode': decision.diagnosticCode,
            'isTerminal': decision.isTerminal,
            if (_logicalIdForPlannerMessage(decision) != null)
              'logicalId': _logicalIdForPlannerMessage(decision),
            if ((decision.providerState['response_id'] ?? '')
                .toString()
                .trim()
                .isNotEmpty)
              'responseId': decision.providerState['response_id'],
          },
        );
      }
      final decisionResponseId = _resolveDecisionResponseId(decision);
      if (decision.toolCalls.isNotEmpty) {
        final reasoningEvent = await _appendVisibleReasoningIfPresent(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          decision: decision,
          scope: 'tool_use',
        );
        if (reasoningEvent != null) {
          yield reasoningEvent;
        }
        await _turnRepository.incrementIteration(turnId);
        yield await _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          content: _decisionStatusContent(decision),
        );

        DecisionToolExecutionSummary? executionSummary;
        final sharedStepId =
            _stepRepository == null || decision.toolCalls.length != 1
                ? null
                : await _stepRepository!.createStep(
                    ChatTurnStep(
                      turnId: turnId,
                      stepIndex: steps.length + 1,
                      providerResponseId: decisionResponseId,
                      providerCallId: decision.toolCalls.length == 1
                          ? decision.toolCalls.single.providerCallId
                          : null,
                      toolName: decision.toolCalls.length == 1
                          ? decision.toolCalls.single.toolName
                          : decision.toolCalls.map((c) => c.toolName).join(','),
                      toolArgsJson: decision.toolCalls.length == 1
                          ? decision.toolCalls.single.arguments
                          : const {},
                      status: ChatTurnStepStatus.planned,
                    ),
                  );
        await for (final update
            in _decisionToolCallExecutor.executeDecisionToolCalls(
          turn: runtimeTurn,
          decision: decision.copyWith(
            providerState: {
              ...decision.providerState,
              if (decisionResponseId != null) 'response_id': decisionResponseId,
            },
          ),
          config: config,
          consecutiveFailures: failures,
          sharedStepId: sharedStepId,
        )) {
          if (update.event != null) {
            yield update.event!;
          }
          if (update.summary != null) {
            executionSummary = update.summary!;
          }
        }

        if (executionSummary?.hasFailedStep == true) {
          failures += 1;
        }

        if (executionSummary?.shouldStopFurtherExecution == true) {
          if (executionSummary?.enteredAwaitingConfirmation == true ||
              executionSummary?.enteredAwaitingUserInteraction == true) {
            break;
          }
          final refreshedTurn = await _turnRepository.getTurn(turnId) ?? turn;
          if (refreshedTurn.status == ChatTurnStatus.running) {
            continue;
          }
          break;
        }

        failures = 0;
        continue;
      }

      if (decision.isTerminal &&
          (decision.assistantMessage ?? '').trim().isNotEmpty) {
        final reasoningEvent = await _appendVisibleReasoningIfPresent(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          decision: decision,
          scope: 'final_answer',
        );
        if (reasoningEvent != null) {
          yield reasoningEvent;
        }
        yield await _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          content: _decisionStatusContent(decision),
        );
        Logger.i(
          _tag,
          'planner chose final response path for turnId=$turnId responsePreview=${_preview(decision.assistantMessage ?? '')}',
        );

        if (decision.diagnosticCode == 'planner_request_failed') {
          Logger.w(
            _tag,
            'planner_request_failed short-circuits final-answer streaming for turnId=$turnId',
          );
          yield await _eventRepository.appendFinalAnswer(
            turnId: turnId,
            groupId: runtimeTurn.groupId,
            content: decision.assistantMessage ?? '规划请求失败',
            payloadJson: _buildFinalAnswerPayload(
              turnId: turnId,
              decision: decision,
            ),
          );
          await _turnRepository.markFailed(
            turnId,
            errorMessage: decision.diagnosticCode ?? 'planner_request_failed',
          );
          break;
        }

        final answerTranscript =
            await _transcriptBuilderService.loadTranscript(turnId);
        final latestAssistantText = decision.assistantMessage ?? '';
        Logger.trace(
          _tag,
          'turn.terminal_response_ready',
          data: {
            'turnId': turnId,
            'responsePreview': _preview(latestAssistantText),
          },
        );
        final verifyResult = await _turnVerifier.verifyCanStop(
          turn: runtimeTurn,
          transcript: answerTranscript,
          steps: _stepRepository == null
              ? const []
              : await _stepRepository!.listSteps(turnId),
          latestAssistantText: latestAssistantText,
          limits: _limits,
        );

        if (verifyResult.canStop) {
          Logger.trace(
            _tag,
            'turn.done',
            data: {
              'turnId': turnId,
              'reason': verifyResult.reason,
            },
          );
          yield await _eventRepository.appendFinalAnswer(
            turnId: turnId,
            groupId: runtimeTurn.groupId,
            content: latestAssistantText,
            payloadJson: _buildFinalAnswerPayload(
              turnId: turnId,
              decision: decision,
            ),
          );
          await _turnRepository.markCompleted(
            turnId,
            stopReason: verifyResult.reason,
            finalResponseText: latestAssistantText,
          );
          break;
        }

        yield await _eventRepository.appendTurnStatus(
          turnId: turnId,
          groupId: runtimeTurn.groupId,
          content: verifyResult.reason,
        );
        Logger.w(
          _tag,
          'stop verifier requested another iteration for turnId=$turnId reason=${verifyResult.reason}',
        );
        Logger.trace(
          _tag,
          'turn.verifier_retry',
          data: {
            'turnId': turnId,
            'reason': verifyResult.reason,
          },
        );
        await _turnRepository.incrementIteration(turnId);
        continue;
      }

      Logger.trace(
        _tag,
        'turn.failed',
        level: LogLevel.error,
        data: {
          'turnId': turnId,
          'reason': 'planner_no_terminal_decision',
        },
      );
      await _turnRepository.markFailed(
        turnId,
        errorMessage: 'planner_no_terminal_decision',
      );
      yield await _eventRepository.appendTurnStatus(
        turnId: turnId,
        groupId: runtimeTurn.groupId,
        content: 'planner_no_terminal_decision',
      );
      break;
    }
  }

  Future<List<ChatEvent>> _consumeSteerFollowUpsBeforePlanner(
    ChatTurn turn,
  ) async {
    final queue = _followUpDispatchQueue;
    final turnId = turn.id;
    if (queue == null || turnId == null) {
      return const <ChatEvent>[];
    }
    final pending = queue.takeSteerForPlanner(turn.groupId);
    if (pending.isEmpty) {
      return const <ChatEvent>[];
    }
    final existingEvents = await _eventRepository.listEventsByTurn(turnId);
    final kind = _isStartUserSegment(existingEvents)
        ? ChatEventUserMessageKind.start
        : ChatEventUserMessageKind.followUp;
    final appendedEvents = <ChatEvent>[];
    for (final pendingEntry in pending) {
      for (final request in _flattenPendingRequests(pendingEntry.request)) {
        appendedEvents.add(await _eventRepository.appendUserMessage(
          turnId: turnId,
          groupId: turn.groupId,
          content: request.text,
          kind: kind,
          attachments: request.attachments,
        ));
      }
    }
    return appendedEvents;
  }

  bool _isStartUserSegment(List<ChatEvent> events) {
    return events
        .every((event) => event.eventType == ChatEventType.userMessage);
  }

  List<SendMessageRequest> _flattenPendingRequests(SendMessageRequest request) {
    return <SendMessageRequest>[
      SendMessageRequest(
        text: request.text,
        attachments: request.attachments,
        allowUnsupportedImageInputAttempt:
            request.allowUnsupportedImageInputAttempt,
        dispatchMode: request.dispatchMode,
      ),
      ...request.additionalStartMessages.expand(_flattenPendingRequests),
    ];
  }

  Future<_AutoCompactionRestartResult?> _maybeAutoCompactAndRestart({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
  }) async {
    final sessionContextService = _sessionContextService;
    if (sessionContextService == null || transcript.isEmpty) {
      return null;
    }
    final boundaryEventId = _resolveAutoCompactionBoundaryEventId(transcript);
    if (boundaryEventId == null) {
      return null;
    }

    final compactionResult =
        await sessionContextService.applyActiveTurnCompaction(
      groupId: turn.groupId,
      currentTurnId: turn.id!,
      currentTurnTranscript: transcript,
      config: config,
      boundaryEventId: boundaryEventId,
    );
    if (compactionResult == null) {
      return null;
    }

    await _turnRepository.markCompleted(
      turn.id!,
      stopReason: 'auto_compacted_continue',
    );
    final continuationTurnId = await _turnRepository.createTurn(
      ChatTurn(
        groupId: turn.groupId,
        status: ChatTurnStatus.running,
        userInput: compactionResult.continuationUserInput,
        goalSummary: turn.goalSummary,
        providerStyle: turn.providerStyle,
        modelName: turn.modelName,
        providerStateJson: _buildContinuationProviderState(turn),
      ),
    );
    final continuationTurn = await _requireTurn(continuationTurnId);
    Logger.i(
      _tag,
      'auto compaction restarted turn ${turn.id} as continuation turn $continuationTurnId',
    );
    return _AutoCompactionRestartResult(
      continuationTurn: continuationTurn,
      boundaryEvent: compactionResult.boundaryEvent,
    );
  }

  int? _resolveAutoCompactionBoundaryEventId(List<ChatEvent> transcript) {
    if (transcript.isEmpty) {
      return null;
    }
    final lastEvent = transcript.last;
    return lastEvent.id ?? lastEvent.sequence;
  }

  Map<String, dynamic>? _buildContinuationProviderState(ChatTurn turn) {
    final runtimeContext =
        turn.providerStateJson?[SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return null;
    }
    return {
      SessionRuntimeMarkerService.runtimeContextKey:
          Map<String, dynamic>.from(runtimeContext),
    };
  }

  Future<List<PlannerContextCarrier>> _buildPlannerCarriers({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    final sessionContextService = _sessionContextService;
    if (sessionContextService != null) {
      return sessionContextService.buildPlannerCarriers(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: currentTurnTranscript,
        config: config,
      );
    }
    return _fallbackPlannerCarriers(currentTurnTranscript);
  }

  List<PlannerContextCarrier> _fallbackPlannerCarriers(
    List<ChatEvent> transcript,
  ) {
    Logger.w(
      _tag,
      'sessionContextService unavailable, using fallback planner carriers',
    );
    final projector = SessionContextProjector();
    final carriers = <PlannerContextCarrier>[];
    for (final event in transcript) {
      if (event.eventType == ChatEventType.assistantTurnSnapshot) {
        final payload = event.payloadJson;
        final apiStyleName = payload?['apiStyle']?.toString();
        final raw = payload?['rawAssistantMessage'];
        if (apiStyleName != null && raw is Map) {
          final style = ChatTurnProviderStyle.values.firstWhere(
            (value) => value.name == apiStyleName,
            orElse: () => ChatTurnProviderStyle.openaiResponses,
          );
          carriers.add(
            RawAssistantCarrier(
              apiStyle: style,
              rawJson: Map<String, dynamic>.from(raw),
            ),
          );
        }
        continue;
      }
      final message = projector.projectEventToContext(event);
      if (message == null) {
        continue;
      }
      switch (message.role) {
        case MessageRole.system:
          carriers.add(SyntheticCarrier.system(message.text));
          break;
        case MessageRole.user:
          carriers.add(SyntheticCarrier.user(message.text));
          break;
        case MessageRole.assistant:
          Logger.w(
            _tag,
            'dropping assistant-projected fallback carrier',
          );
          break;
      }
    }
    return carriers;
  }

  @visibleForTesting
  List<PlannerContextCarrier> debugFallbackPlannerCarriersForTest(
    List<ChatEvent> transcript,
  ) {
    return _fallbackPlannerCarriers(transcript);
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

  Future<ChatEvent?> _appendVisibleReasoningIfPresent({
    required int turnId,
    required int groupId,
    required ModelTurnDecision decision,
    required String scope,
  }) {
    final visibleReasoning = decision.visibleReasoning?.trim();
    if (visibleReasoning == null || visibleReasoning.isEmpty) {
      return Future.value(null);
    }
    return _eventRepository.appendAssistantReasoningDelta(
      turnId: turnId,
      groupId: groupId,
      content: visibleReasoning,
      scope: scope,
      payloadJson: _buildReasoningPayload(
        turnId: turnId,
        decision: decision,
      ),
    );
  }

  Map<String, dynamic>? _buildReasoningPayload({
    required int turnId,
    required ModelTurnDecision decision,
  }) {
    final identity = _readStreamingPreviewIdentity(decision);
    final messageId = identity?['messageId']?.toString().trim();
    final blockId = identity?['reasoningBlockId']?.toString().trim();
    final logicalId = _logicalIdForReasoningDecision(
      turnId: turnId,
      decision: decision,
    );
    if ((messageId == null ||
            messageId.isEmpty ||
            blockId == null ||
            blockId.isEmpty) &&
        logicalId == null) {
      return null;
    }
    return {
      if (messageId != null && messageId.isNotEmpty)
        'previewMessageId': messageId,
      if (blockId != null && blockId.isNotEmpty)
        'previewContentBlockId': blockId,
      if (logicalId != null) 'logicalId': logicalId,
      if (_resolveDecisionResponseId(decision) != null)
        'responseId': _resolveDecisionResponseId(decision),
    };
  }

  Map<String, dynamic>? _buildFinalAnswerPayload({
    required int turnId,
    required ModelTurnDecision decision,
  }) {
    final identity = _readStreamingPreviewIdentity(decision);
    final messageId = identity?['messageId']?.toString().trim();
    final blockId = identity?['textBlockId']?.toString().trim();
    final payload = <String, dynamic>{
      'isFinalAnswer': true,
      'logicalId': 'final:$turnId',
      if (_resolveDecisionResponseId(decision) != null)
        'responseId': _resolveDecisionResponseId(decision),
    };
    if (messageId != null &&
        messageId.isNotEmpty &&
        blockId != null &&
        blockId.isNotEmpty) {
      payload['previewMessageId'] = messageId;
      payload['previewContentBlockId'] = blockId;
    }
    return payload;
  }

  String? _logicalIdForReasoningDecision({
    required int turnId,
    required ModelTurnDecision decision,
  }) {
    final responseId = _resolveDecisionResponseId(decision);
    if (decision.toolCalls.isNotEmpty) {
      if (responseId == null || responseId.isEmpty) {
        return null;
      }
      return 'toolReasoning:$responseId';
    }
    return 'finalReasoning:$turnId';
  }

  String? _logicalIdForPlannerMessage(ModelTurnDecision decision) {
    if (decision.toolCalls.isEmpty) {
      return null;
    }
    final responseId = _resolveDecisionResponseId(decision);
    if (responseId == null || responseId.isEmpty) {
      return null;
    }
    return 'toolText:$responseId';
  }

  Map<String, dynamic>? _readStreamingPreviewIdentity(
      ModelTurnDecision decision) {
    final identity = decision.providerState['streaming_preview_identity'];
    if (identity is Map<String, dynamic>) {
      return identity;
    }
    if (identity is Map) {
      return identity.cast<String, dynamic>();
    }
    return null;
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
        content: toolInvocation?.summary ?? invocation.summary,
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
        payloadJson: toolResult == null
            ? null
            : {
                ...toolResult.toJson(),
                if ((invocation.providerCallId ?? '').trim().isNotEmpty)
                  'providerCallId': invocation.providerCallId!.trim(),
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
        return;
      }
      return;
    }

    Logger.d(
      _tag,
      'tool execution succeeded for ${invocation.toolName}: ${toolResult.summary}',
    );
    await _applyToolRuntimeContextUpdates(
      turnId: turnId,
      workspaceChangeReminder:
          toolResult.data['workspaceChangeReminder'] as String?,
      workspaceId: toolResult.data['workspaceId'] as String?,
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
        if ((invocation.providerCallId ?? '').trim().isNotEmpty)
          'providerCallId': invocation.providerCallId!.trim(),
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

    if (resumeLoopAfterSuccess) {
      final resumedTurn = await _turnRepository.getTurn(turnId) ?? turn;
      yield* _continueTurnLoop(
        turn: resumedTurn,
        config: config,
        consecutiveFailures: 0,
      );
    }
  }

  Future<void> _applyToolRuntimeContextUpdates({
    required int turnId,
    String? workspaceChangeReminder,
    String? workspaceId,
  }) async {
    if ((workspaceChangeReminder == null ||
            workspaceChangeReminder.trim().isEmpty) &&
        (workspaceId == null || workspaceId.trim().isEmpty)) {
      return;
    }
    final turn = await _turnRepository.getTurn(turnId);
    if (turn == null) {
      return;
    }
    final providerState =
        Map<String, dynamic>.from(turn.providerStateJson ?? const {});
    final runtimeContext = Map<String, dynamic>.from(
      providerState[SessionRuntimeMarkerService.runtimeContextKey] as Map? ??
          const <String, dynamic>{},
    );
    if (workspaceChangeReminder != null &&
        workspaceChangeReminder.trim().isNotEmpty) {
      runtimeContext[SessionRuntimeMarkerService.workspaceChangeReminderKey] =
          workspaceChangeReminder.trim();
    }
    if (workspaceId != null && workspaceId.trim().isNotEmpty) {
      runtimeContext['workspace_id'] = workspaceId.trim();
    }
    providerState[SessionRuntimeMarkerService.runtimeContextKey] =
        runtimeContext;
    await _turnRepository.updateRuntimeState(
      turnId,
      providerStyle: turn.providerStyle,
      modelName: turn.modelName,
      providerStateJson: providerState,
    );
  }

  Future<ChatTurn> _requireTurn(int turnId) async {
    final turn = await _turnRepository.getTurn(turnId);
    if (turn == null) {
      throw StateError('Turn $turnId not found');
    }
    return turn;
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

  Map<String, dynamic> _buildToolInvocationPayload({
    required ToolInvocation invocation,
    required ToolAccessSnapshot? toolAccess,
  }) {
    return {
      ...invocation.toJson(),
      if (toolAccess != null) 'toolAccess': toolAccess.toJson(),
    };
  }

  String _formatUserInteractionTranscript(
    AskUserQuestionRequest request,
    AskUserQuestionResponse response,
  ) {
    final lines = <String>['User answered AskUserQuestion:'];
    for (final question in request.questions) {
      if (!response.answersByQuestionId.containsKey(question.id)) {
        continue;
      }
      final answer = response.answersByQuestionId[question.id] ?? '';
      final title =
          question.header.trim().isEmpty ? question.id : question.header;
      final normalizedAnswer =
          answer.trim().isEmpty ? '(skipped)' : answer.trim();
      lines.add('- $title: $normalizedAnswer');
    }
    return lines.join('\n');
  }
}

class _TurnUserMessageSeed {
  const _TurnUserMessageSeed({
    required this.text,
    required this.kind,
    this.attachments = const <ChatAttachment>[],
  });

  final String text;
  final ChatEventUserMessageKind kind;
  final List<ChatAttachment> attachments;

  factory _TurnUserMessageSeed.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString().trim();
    final kind = ChatEventUserMessageKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => ChatEventUserMessageKind.start,
    );
    final rawAttachments = json['attachments'];
    final attachments = rawAttachments is! List
        ? const <ChatAttachment>[]
        : rawAttachments
            .whereType<Map>()
            .map(
              (item) => ChatAttachment.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false);
    return _TurnUserMessageSeed(
      text: json['text']?.toString() ?? '',
      kind: kind,
      attachments: attachments,
    );
  }
}

class _AutoCompactionRestartResult {
  final ChatTurn continuationTurn;
  final ChatEvent? boundaryEvent;

  const _AutoCompactionRestartResult({
    required this.continuationTurn,
    required this.boundaryEvent,
  });
}
