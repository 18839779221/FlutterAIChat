import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat/send_message_request.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/skill/invoked_skill_context.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:ai_chat/services/follow_up_dispatch_queue.dart';
import 'package:ai_chat/services/agent_planner_service.dart'
    show PlannerRequestTraceEvent, PlannerRequestTraceStage;
import 'package:ai_chat/services/session_runtime_marker_service.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/services/skills/explicit_skill_invocation_parser.dart';
import 'package:ai_chat/services/skills/invoked_skill_reminder_builder.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_event_processor.dart';

const String traceTurnIdPayloadKey = 'traceTurnId';
const String traceTurnIdRuntimeContextKey = 'trace_turn_id';

abstract class ChatSendCoordinator {
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  });

  Future<void> sendMessage(
    String text, {
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  });

  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  });

  Future<void> submitQuestionAnswers(
    ChatMessage message, {
    required AskUserQuestionResponse response,
  });

  Future<void> cancelToolInvocation(ChatMessage message);
}

class DefaultChatSendCoordinator implements ChatSendCoordinator {
  static const String _tag = 'ChatSendCoordinator';

  final Ref _ref;

  DefaultChatSendCoordinator(this._ref);

  @override
  Future<void> sendMessage(
    String text, {
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  }) async {
    await sendMessageRequest(
      SendMessageRequest(text: text),
      scheduleAutoSummary: scheduleAutoSummary,
      cancelActiveStream: cancelActiveStream,
    );
  }

  void recordPlannerRequestTrace(PlannerRequestTraceEvent event) {
    final traceRecorder = _ref.read(streamingTraceRecorderProvider.notifier);
    final persistentTraceRecorder = _ref.read(traceRecorderProvider);
    final traceId = streamingTraceIdForTurn(event.turnId);
    final details = <String, dynamic>{
      'agentTurnId': event.turnId,
      'requestId': event.requestId,
      if ((event.phase ?? '').trim().isNotEmpty) 'phase': event.phase!.trim(),
      if ((event.toolName ?? '').trim().isNotEmpty)
        'toolName': event.toolName!.trim(),
    };
    switch (event.stage) {
      case PlannerRequestTraceStage.requestStarted:
        traceRecorder.recordStage(
          traceId: traceId,
          turnId: event.turnId.toString(),
          stage: StreamingTraceStage.modelRequestStarted,
          timestamp: event.timestamp,
          details: details,
        );
        _recordPersistentPlannerTrace(
          recorder: persistentTraceRecorder,
          event: event,
          stage: ChatTraceStage.llmRequestStart,
          status: ChatTraceStatus.started,
          summary: 'planner request started',
          details: details,
        );
        break;
      case PlannerRequestTraceStage.firstChunk:
        traceRecorder.recordStage(
          traceId: traceId,
          turnId: event.turnId.toString(),
          stage: StreamingTraceStage.modelFirstChunk,
          timestamp: event.timestamp,
          details: details,
        );
        _recordPersistentPlannerTrace(
          recorder: persistentTraceRecorder,
          event: event,
          stage: ChatTraceStage.llmFirstToken,
          status: ChatTraceStatus.success,
          summary: 'planner first chunk received',
          details: details,
        );
        break;
      case PlannerRequestTraceStage.requestCompleted:
        traceRecorder.recordStage(
          traceId: traceId,
          turnId: event.turnId.toString(),
          stage: StreamingTraceStage.modelRequestCompleted,
          timestamp: event.timestamp,
          details: details,
        );
        _recordPersistentPlannerTrace(
          recorder: persistentTraceRecorder,
          event: event,
          stage: ChatTraceStage.llmDone,
          status: ChatTraceStatus.success,
          summary: 'planner request completed',
          details: details,
        );
        break;
    }
  }

  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  }) async {
    Logger.i(
      _tag,
      'sendMessageRequest entered',
    );
    final outboundRequests = _flattenSendRequests(request);
    final text = outboundRequests.first.text;
    final attachments =
        outboundRequests.expand((candidate) => candidate.attachments).toList();
    final allowUnsupportedImageInputAttempt = outboundRequests.any(
      (candidate) => candidate.allowUnsupportedImageInputAttempt,
    );
    Logger.runtime(
      _tag,
      'sendMessageRequest payload received',
      data: {
        'textLength': text.length,
        'attachmentCount': attachments.length,
        'allowUnsupportedImageInputAttempt': allowUnsupportedImageInputAttempt,
        'attachmentKinds':
            attachments.map((attachment) => attachment.kind.name).join(','),
        'attachmentStatuses':
            attachments.map((attachment) => attachment.status.name).join(','),
      },
    );
    if (outboundRequests.every(
      (candidate) =>
          candidate.text.trim().isEmpty && candidate.attachments.isEmpty,
    )) {
      return;
    }

    final pendingQueue = _ref.read(followUpDispatchQueueProvider);
    final activeSendPhase = _ref.read(sendPhaseProvider);
    if (activeSendPhase != ChatSendPhase.idle) {
      pendingQueue.enqueue(
        groupId: _ref.read(currentGroupProvider)?.id,
        request: request,
      );
      Logger.runtime(
        _tag,
        'queued follow-up request while turn remains active',
        data: {
          'dispatchMode': request.dispatchMode.name,
          'pendingCount': pendingQueue
              .pendingCountForGroup(_ref.read(currentGroupProvider)?.id),
        },
      );
      return;
    }

    var currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup == null) {
      Logger.w(
          _tag, 'current group missing before send, creating a draft group');
      final systemPrompt = _ref.read(systemPromptProvider);
      currentGroup = ChatGroup(
        title: '新对话',
        systemPrompt: systemPrompt,
      );
      _ref.read(currentGroupProvider.notifier).state = currentGroup;
      _ref.read(messagesProvider.notifier).clearMessages();
      _ref.read(hasMoreMessagesProvider.notifier).state = false;
      _ref.read(isInitializingProvider.notifier).state = false;
    }
    for (final outboundRequest in outboundRequests) {
      final imageSupportFailure = await _validateAttachmentSupport(
        attachments: outboundRequest.attachments,
        currentGroup: currentGroup,
        llm: _ref.read(chatServiceProvider).llm,
        allowUnsupportedImageInputAttempt:
            outboundRequest.allowUnsupportedImageInputAttempt,
      );
      if (imageSupportFailure != null) {
        Logger.w(
          _tag,
          'image support validation rejected request: $imageSupportFailure',
        );
        await _appendVisibleSendFailureMessage(
          groupId: currentGroup.id,
          error: Exception(imageSupportFailure),
        );
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.idle,
            );
        return;
      }
    }
    var cancellationRequested = false;

    Future<void> requestPreparingCancellation() async {
      cancellationRequested = true;
    }

    _ref.read(focusNodeProvider).unfocus();
    Logger.d(
      _tag,
      '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...',
    );

    cancelActiveStream();
    _ref.read(activeSendCancellationProvider.notifier).state =
        requestPreparingCancellation;
    _ref.read(chatSendStateProvider.notifier).update(
          phase: ChatSendPhase.preparing,
          clearStatusText: true,
        );
    final traceRecorder = _ref.read(traceRecorderProvider);
    final turnId = traceRecorder.newTurnId();
    traceRecorder.record(
      turnId: turnId,
      stage: ChatTraceStage.sendStart,
      status: ChatTraceStatus.started,
      summary: '开始发送消息',
      data: {
        'groupId': currentGroup.id,
        'userMessagePreview': text.substring(0, text.length.clamp(0, 80)),
        'attachmentCount': attachments.length,
      },
    );

    if (currentGroup.id == null) {
      try {
        final dbHelper = _ref.read(databaseProvider);
        final newGroup = currentGroup.copyWith(title: text);
        final groupId = await dbHelper.insertGroup(newGroup);
        final currentRuntime = _ref.read(currentSessionRuntimeConfigProvider);
        if (currentRuntime != null) {
          final persistedRuntime = SessionRuntimeConfig(
            groupId: groupId,
            providerId: currentRuntime.providerId,
            modelId: currentRuntime.modelId,
            providerStyle: currentRuntime.providerStyle,
          );
          await dbHelper.insertSessionRuntimeConfig(persistedRuntime);
          _ref.read(currentSessionRuntimeConfigProvider.notifier).state =
              persistedRuntime;
        }
        Logger.runtime(
          _tag,
          'persisted draft group for send',
          data: {
            'groupId': groupId,
            'groupTitle': newGroup.title,
          },
        );
        _ref.read(currentGroupProvider.notifier).state =
            newGroup.copyWith(id: groupId);
        await _loadGroups();
      } catch (e) {
        Logger.e(_tag, '保存新分组失败', e);
        traceRecorder.record(
          turnId: turnId,
          stage: ChatTraceStage.sendFailed,
          status: ChatTraceStatus.failure,
          summary: '保存新分组失败',
          data: {
            'error': e.toString(),
          },
        );
        return;
      }
    }

    final explicitSkillParser = ExplicitSkillInvocationParser(
      skillRuntimeService: _ref.read(skillRuntimeServiceProvider),
    );
    final preparedInputs = <_PreparedOutboundUserMessage>[];
    InvokedSkillContext? explicitInvokedSkill;
    for (final outboundRequest in outboundRequests) {
      final explicitSkill =
          await explicitSkillParser.parse(outboundRequest.text);
      explicitInvokedSkill ??= explicitSkill.invokedSkill;
      final sanitizedText = explicitSkill.cleanedUserText.trim().isEmpty
          ? outboundRequest.text
          : explicitSkill.cleanedUserText;
      final userMessage = ChatMessage(
        text: sanitizedText,
        role: MessageRole.user,
        status: MessageStatus.completed,
        attachments: outboundRequest.attachments,
        referenceJson: outboundRequest.attachments.isEmpty
            ? null
            : {
                'attachments': outboundRequest.attachments
                    .map((attachment) => attachment.toJson())
                    .toList(),
              },
      );
      preparedInputs.add(
        _PreparedOutboundUserMessage(
          request: outboundRequest,
          text: sanitizedText,
          userMessage: userMessage,
        ),
      );
      _ref.read(pendingPinnedUserMessageStableKeyProvider.notifier).state =
          'user-${userMessage.timestamp.microsecondsSinceEpoch}';
      _ref.read(messagesProvider.notifier).addMessage(userMessage);
      Logger.runtime(
        _tag,
        'user message added to in-memory timeline',
        data: {
          'textLength': sanitizedText.length,
          'attachmentCount': outboundRequest.attachments.length,
        },
      );
    }
    await Future.delayed(const Duration(milliseconds: 1));

    try {
      final dbHelper = _ref.read(databaseProvider);
      final currentGroupId = _ref.read(currentGroupProvider)!.id!;
      final runtimeMarkerService =
          _ref.read(sessionRuntimeMarkerServiceProvider);
      final runtimeMarkerPreparation =
          await runtimeMarkerService.prepareForUserMessage(
        groupId: currentGroupId,
      );
      for (final preparedInput in preparedInputs) {
        final shouldPersistUserTextMessage =
            preparedInput.text.trim().isNotEmpty ||
                preparedInput.userMessage.attachments.isEmpty;

        if (shouldPersistUserTextMessage) {
          Logger.d(_tag, '保存用户消息到数据库...');
          final userMessageId = await dbHelper.insertMessage(
            preparedInput.userMessage,
            currentGroupId,
          );
          preparedInput.userMessage.id = userMessageId;
          Logger.runtime(
            _tag,
            'user message persisted',
            data: {
              'messageId': userMessageId,
              'groupId': currentGroupId,
              'attachmentCount': preparedInput.userMessage.attachments.length,
            },
          );
          if (preparedInput.userMessage.attachments.isNotEmpty) {
            await dbHelper.insertMessageAttachments(
              userMessageId,
              preparedInput.userMessage.attachments,
            );
            Logger.runtime(
              _tag,
              'user attachments persisted',
              data: {
                'messageId': userMessageId,
                'attachmentCount': preparedInput.userMessage.attachments.length,
                'attachmentPaths': preparedInput.userMessage.attachments
                    .map((attachment) => attachment.localPath ?? '')
                    .join(','),
              },
            );
          }
        } else {
          Logger.runtime(
            _tag,
            'skip persisting empty user text message; attachments remain turn-scoped only',
            data: {
              'groupId': currentGroupId,
              'attachmentCount': preparedInput.userMessage.attachments.length,
            },
          );
        }
      }

      if (cancellationRequested) {
        await _projectCancelledTurnOutcome(
          groupId: currentGroupId,
          assistantMessageId: null,
        );
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.idle,
            );
        return;
      }

      final turnHarness = _ref.read(turnHarnessProvider);
      if (turnHarness == null) {
        throw StateError('turnHarnessProvider is required');
      }
      await _sendMessageWithAgentLoop(
        text: preparedInputs.first.text,
        currentGroupId: currentGroupId,
        preparedInputs: preparedInputs,
        turnId: turnId,
        harness: turnHarness,
        runtimeMarkerPreparation: runtimeMarkerPreparation,
        runtimeMarkerService: runtimeMarkerService,
        explicitInvokedSkill: explicitInvokedSkill,
        scheduleAutoSummary: scheduleAutoSummary,
        cancelActiveStream: cancelActiveStream,
      );
      await _recordRuntimeImageInputSupportSuccessIfNeeded(attachments);
    } catch (e, stackTrace) {
      final handledFailure = e is _HandledSendFailure ? e : null;
      final rawError = handledFailure?.error ?? e;
      Logger.e(_tag, '发送消息过程中出错', rawError);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      traceRecorder.record(
        turnId: turnId,
        stage: ChatTraceStage.sendFailed,
        status: ChatTraceStatus.failure,
        summary: '发送消息过程中出错',
        data: {
          'error': rawError.toString(),
        },
      );
      if (handledFailure == null) {
        await _appendVisibleSendFailureMessage(
          groupId: _ref.read(currentGroupProvider)?.id,
          error: rawError,
        );
      }
      _ref.read(chatSendStateProvider.notifier).update(
            isGenerating: false,
            phase: ChatSendPhase.idle,
          );
    } finally {
      if (identical(
        _ref.read(activeSendCancellationProvider),
        requestPreparingCancellation,
      )) {
        _ref.read(activeSendCancellationProvider.notifier).state = null;
      }
    }
  }

  Future<void> _sendMessageWithAgentLoop({
    required String text,
    required int currentGroupId,
    required List<_PreparedOutboundUserMessage> preparedInputs,
    required String turnId,
    required TurnHarness harness,
    required SessionRuntimeMarkerPreparation runtimeMarkerPreparation,
    required SessionRuntimeMarkerService runtimeMarkerService,
    required InvokedSkillContext? explicitInvokedSkill,
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  }) async {
    final dbHelper = _ref.read(databaseProvider);
    final traceRecorder = _ref.read(traceRecorderProvider);
    final turnRepository = ChatTurnRepository(dbHelper);
    final runtimeConfig = _ref.read(currentSessionRuntimeConfigProvider);
    final createdTurn = ChatTurn(
      groupId: currentGroupId,
      status: ChatTurnStatus.running,
      userInput: text,
      providerStyle: runtimeConfig?.providerStyle,
      modelName: runtimeConfig?.modelId,
      providerStateJson: _buildTurnRuntimeContext(
        runtimeMarkerService: runtimeMarkerService,
        runtimeMarkerPreparation: runtimeMarkerPreparation,
        explicitInvokedSkill: explicitInvokedSkill,
        preparedInputs: preparedInputs,
        traceTurnId: turnId,
      ),
    );
    final turnRecordId = await turnRepository.createTurn(createdTurn);
    final persistedTurn = createdTurn.copyWith(id: turnRecordId);
    _ref.read(streamingTraceRecorderProvider.notifier).recordStage(
      traceId: streamingTraceIdForTurn(turnRecordId),
      turnId: turnRecordId.toString(),
      stage: StreamingTraceStage.turnStarted,
      timestamp: preparedInputs.first.userMessage.timestamp,
      details: {
        'userMessagePreview': text.substring(0, text.length.clamp(0, 80)),
      },
    );
    await runtimeMarkerService.persistInjectedDate(
      groupId: currentGroupId,
      currentDate: runtimeMarkerPreparation.currentDate,
    );
    final config = await _buildChatConfig();

    final processor = AgentEventProcessor(
      ref: _ref,
      groupId: currentGroupId,
      traceTurnId: turnId,
      agentTurnId: turnRecordId,
      hooks: AgentEventHooks(
        onAssistantToolConfirmation: (event) {
          traceRecorder.record(
            turnId: turnId,
            stage: ChatTraceStage.sendDone,
            status: ChatTraceStatus.success,
            summary: '发送进入确认态',
            data: {
              'phase': ChatSendPhase.awaitingConfirmation.name,
              'toolName': event.payloadJson?['toolName'],
            },
          );
        },
        onFinalAnswer: (event) {
          traceRecorder.record(
            turnId: turnId,
            stage: ChatTraceStage.sendDone,
            status: ChatTraceStatus.success,
            summary: '发送完成',
            data: {
              'turnRecordId': turnRecordId,
            },
          );
          scheduleAutoSummary();
        },
      ),
    );
    Future<void> Function()? registeredCancelActiveSend;
    await _runAgentEventStream(
      stream: harness.runTurn(
        turn: persistedTurn,
        config: config,
      ),
      processor: processor,
      onError: (error, stackTrace, completion) {
        traceRecorder.record(
          turnId: turnId,
          stage: ChatTraceStage.sendFailed,
          status: ChatTraceStatus.failure,
          summary: 'agent loop 发送失败',
          data: {
            'error': error.toString(),
          },
        );
        _syncAssistantFailureState(
          groupId: currentGroupId,
          assistantMessageId: processor.assistantMessageId,
          rawError: error,
        );
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.idle,
            );
        if (!completion.isCompleted) {
          completion.completeError(_HandledSendFailure(error), stackTrace);
        }
      },
      onCompletionCreated: (completion) async {
        Future<void> cancelActiveSend() async {
          if (!completion.isCompleted) {
            await turnRepository.markCancelled(
              turnRecordId,
              stopReason: 'cancelled_by_user',
            );
            await _projectCancelledTurnOutcome(
              groupId: currentGroupId,
              assistantMessageId: processor.assistantMessageId,
            );
            completion.complete();
          }
        }

        registeredCancelActiveSend = cancelActiveSend;
        _ref.read(activeSendCancellationProvider.notifier).state =
            cancelActiveSend;
      },
      onSuccess: () async {
        await _finalizeTurnOutcome(
          groupId: currentGroupId,
          turnId: turnRecordId,
          processor: processor,
          scheduleAutoSummary: scheduleAutoSummary,
          cancelActiveStream: cancelActiveStream,
        );
      },
      onFinally: () async {
        if (identical(
          _ref.read(activeSendCancellationProvider),
          registeredCancelActiveSend,
        )) {
          _ref.read(activeSendCancellationProvider.notifier).state = null;
        }
      },
    );
  }

  Map<String, dynamic> _buildTurnRuntimeContext({
    required SessionRuntimeMarkerService runtimeMarkerService,
    required SessionRuntimeMarkerPreparation runtimeMarkerPreparation,
    required InvokedSkillContext? explicitInvokedSkill,
    required List<_PreparedOutboundUserMessage> preparedInputs,
    required String traceTurnId,
  }) {
    final context = runtimeMarkerService.buildTurnRuntimeContext(
      runtimeMarkerPreparation,
    );
    final runtimeContext = Map<String, dynamic>.from(
      context[SessionRuntimeMarkerService.runtimeContextKey] as Map,
    );
    runtimeContext[traceTurnIdRuntimeContextKey] = traceTurnId;
    runtimeContext['seeded_user_messages'] = preparedInputs
        .map(
          (input) => {
            'text': input.text,
            'kind': ChatEventUserMessageKind.start.name,
            if (input.userMessage.attachments.isNotEmpty)
              'attachments': input.userMessage.attachments
                  .map((attachment) => attachment.toJson())
                  .toList(),
          },
        )
        .toList(growable: false);
    final attachments = preparedInputs
        .expand((input) => input.userMessage.attachments)
        .toList(growable: false);
    if (attachments.isNotEmpty) {
      runtimeContext['user_attachments'] =
          attachments.map((attachment) => attachment.toJson()).toList();
      Logger.temp(
        _tag,
        'attachments.runtime_context_staged',
        reason: 'diagnose_image_attachment_context_chain',
        data: {
          'attachmentCount': attachments.length,
          'localIds':
              attachments.map((attachment) => attachment.localId).toList(),
          'statuses':
              attachments.map((attachment) => attachment.status.name).toList(),
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
    }
    if (explicitInvokedSkill == null) {
      return {
        ...context,
        SessionRuntimeMarkerService.runtimeContextKey: runtimeContext,
      };
    }
    final reminder =
        const InvokedSkillReminderBuilder().build(explicitInvokedSkill);
    runtimeContext['explicit_skill_reminder'] = reminder;
    runtimeContext['explicit_skill_context'] = explicitInvokedSkill.toJson();
    return {
      ...context,
      SessionRuntimeMarkerService.runtimeContextKey: runtimeContext,
    };
  }

  Future<void> _appendVisibleSendFailureMessage({
    required int? groupId,
    required Object error,
  }) async {
    if (groupId == null) {
      return;
    }
    await _insertAssistantStatusMessage(
      groupId: groupId,
      text: _formatSendFailureText(error),
      status: MessageStatus.failed,
    );
  }

  Future<void> _runAgentEventStream({
    required Stream<ChatEvent> stream,
    required AgentEventProcessor processor,
    required void Function(
      Object error,
      StackTrace stackTrace,
      Completer<void> completion,
    ) onError,
    required Future<void> Function() onSuccess,
    Future<void> Function(Completer<void> completion)? onCompletionCreated,
    Future<void> Function()? onFinally,
  }) async {
    final completion = Completer<void>();
    final subscription = stream.asyncMap((event) async {
      await processor.handle(event);
    }).listen(
      (_) {},
      onError: (error, stackTrace) {
        unawaited(processor.dispose());
        onError(error, stackTrace, completion);
      },
      onDone: () {
        if (!completion.isCompleted) {
          completion.complete();
        }
      },
      cancelOnError: true,
    );

    _ref.read(streamSubscriptionProvider.notifier).state = subscription;
    if (onCompletionCreated != null) {
      await onCompletionCreated(completion);
    }
    try {
      await completion.future;
      await onSuccess();
    } finally {
      await processor.dispose();
      if (identical(_ref.read(streamSubscriptionProvider), subscription)) {
        _ref.read(streamSubscriptionProvider.notifier).state = null;
      }
      if (onFinally != null) {
        await onFinally();
      }
    }
  }

  Future<ChatConfig> _buildChatConfig() async {
    LLMConfig? runtimeConfigOverride;
    LLMConfig? sideRuntimeConfigOverride;
    final runtimeConfig = _ref.read(currentSessionRuntimeConfigProvider);
    if (runtimeConfig != null) {
      final resolver = _ref.read(sessionLlmConfigResolverProvider);
      runtimeConfigOverride = await resolver.resolve(runtimeConfig);
      sideRuntimeConfigOverride = await resolver.resolve(
        runtimeConfig,
        slot: SessionRuntimeSlot.side,
      );
    }
    return ChatConfig(
      systemPrompt: '',
      userSystemPrompt: _ref.read(systemPromptProvider) ?? '',
      runtimeConfigOverride: runtimeConfigOverride,
      sideRuntimeConfigOverride: sideRuntimeConfigOverride,
    );
  }

  Future<void> _finalizeTurnOutcome({
    required int groupId,
    required int turnId,
    required AgentEventProcessor processor,
    VoidCallback? scheduleAutoSummary,
    VoidCallback? cancelActiveStream,
  }) async {
    if (processor.hasPendingConfirmation) {
      _ref.read(chatSendStateProvider.notifier).update(
            isGenerating: false,
            phase: ChatSendPhase.awaitingConfirmation,
          );
      return;
    }

    final turnRepository = ChatTurnRepository(_ref.read(databaseProvider));
    final turn = await turnRepository.getTurn(turnId);
    if (turn == null) {
      _ref.read(chatSendStateProvider.notifier).update(
            isGenerating: false,
            phase: ChatSendPhase.idle,
          );
      return;
    }

    if (turn.status == ChatTurnStatus.failed &&
        !processor.receivedFinalAnswer) {
      await _persistInterruptedPartialContextIfNeeded(
        turn: turn,
        assistantMessageId: processor.assistantMessageId,
      );
      await _upsertAssistantFailureMessage(
        groupId: groupId,
        assistantMessageId: processor.assistantMessageId,
        text: _formatTurnFailureText(turn),
      );
    }
    if (turn.status == ChatTurnStatus.cancelled &&
        !processor.receivedFinalAnswer) {
      await _persistInterruptedPartialContextIfNeeded(
        turn: turn,
        assistantMessageId: processor.assistantMessageId,
      );
    }

    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.idle,
        );
    await _startQueuedNextTurnIfNeeded(
      groupId: groupId,
      scheduleAutoSummary: scheduleAutoSummary ?? () {},
      cancelActiveStream: cancelActiveStream ?? () {},
    );
  }

  Future<void> _startQueuedNextTurnIfNeeded({
    required int groupId,
    required VoidCallback scheduleAutoSummary,
    required VoidCallback cancelActiveStream,
  }) async {
    final pending =
        _ref.read(followUpDispatchQueueProvider).takeAllForNextTurn(groupId);
    if (pending.isEmpty) {
      return;
    }
    final requests = pending
        .expand((entry) => _flattenSendRequests(entry.request))
        .toList(growable: false);
    if (requests.isEmpty) {
      return;
    }
    await sendMessageRequest(
      SendMessageRequest(
        text: requests.first.text,
        attachments: requests.first.attachments,
        allowUnsupportedImageInputAttempt:
            requests.first.allowUnsupportedImageInputAttempt,
        dispatchMode: SendMessageDispatchMode.queue,
        additionalStartMessages: requests.skip(1).toList(growable: false),
      ),
      scheduleAutoSummary: scheduleAutoSummary,
      cancelActiveStream: cancelActiveStream,
    );
  }

  Future<void> _projectCancelledTurnOutcome({
    required int groupId,
    required int? assistantMessageId,
  }) async {
    final activeToolMessage = _resolveLatestActiveToolMessageInCurrentTurn();
    if (activeToolMessage != null) {
      await _markToolMessageCancelled(activeToolMessage);
    }

    if (_hasVisibleInterruptedAssistantText(assistantMessageId) ||
        activeToolMessage != null) {
      return;
    }

    final runtimePreviewText = _resolveLatestRuntimePreviewResponseText();
    if (runtimePreviewText != null) {
      await _insertAssistantStatusMessage(
        groupId: groupId,
        text: runtimePreviewText,
        status: MessageStatus.interrupted,
      );
      return;
    }

    await _upsertAssistantCancelledMessage(
      groupId: groupId,
      assistantMessageId: assistantMessageId,
      text: _cancelledTurnSummaryText(),
    );
  }

  Future<void> _persistInterruptedPartialContextIfNeeded({
    required ChatTurn turn,
    required int? assistantMessageId,
  }) async {
    final partialText = _resolveInterruptedAssistantText(assistantMessageId);
    if (partialText == null || partialText.trim().isEmpty) {
      return;
    }
    final turnId = turn.id;
    if (turnId == null) {
      return;
    }
    final eventRepository = _ref.read(chatEventRepositoryProvider);
    final existingEvents = await eventRepository.listEventsByTurn(turnId);
    if (existingEvents.any(
      (event) =>
          event.eventType == ChatEventType.assistantTurnSnapshot &&
          event.payloadJson?['rawAssistantMessage'] is Map &&
          (event.payloadJson?['rawAssistantMessage']
                  as Map)['interruptedPartialRecovery'] ==
              true,
    )) {
      return;
    }
    await eventRepository.appendAssistantTurnSnapshot(
      turnId: turnId,
      groupId: turn.groupId,
      apiStyle: turn.providerStyle ?? ChatTurnProviderStyle.openaiResponses,
      rawAssistantMessageJson: _buildInterruptedAssistantSnapshot(
        text: partialText,
        providerStyle:
            turn.providerStyle ?? ChatTurnProviderStyle.openaiResponses,
      ),
    );
    await eventRepository.appendUserMessage(
      turnId: turnId,
      groupId: turn.groupId,
      content: _buildInterruptedReminderText(turn.status),
      kind: ChatEventUserMessageKind.systemReminder,
      extraPayloadJson: const {
        'interruptedPreviousResponse': true,
      },
    );
  }

  String? _resolveInterruptedAssistantText(int? assistantMessageId) {
    final visibleAssistantMessage = assistantMessageId == null
        ? null
        : _findMessageById(assistantMessageId);
    final visibleText = visibleAssistantMessage?.text.trim();
    if (visibleText != null && visibleText.isNotEmpty) {
      return visibleAssistantMessage!.text;
    }
    return _resolveLatestRuntimePreviewResponseText();
  }

  String _buildInterruptedReminderText(ChatTurnStatus status) {
    if (status == ChatTurnStatus.cancelled) {
      return 'User interrupted the previous response before it completed.';
    }
    return 'The previous response was interrupted before it completed.';
  }

  Map<String, dynamic> _buildInterruptedAssistantSnapshot({
    required String text,
    required ChatTurnProviderStyle providerStyle,
  }) {
    return switch (providerStyle) {
      ChatTurnProviderStyle.openaiChatCompletions => {
          'role': 'assistant',
          'content': text,
          'interruptedPartialRecovery': true,
        },
      ChatTurnProviderStyle.openaiResponses => {
          'interruptedPartialRecovery': true,
          'output': [
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {
                  'type': 'output_text',
                  'text': text,
                  'annotations': const [],
                },
              ],
            },
          ],
        },
      ChatTurnProviderStyle.anthropicMessages => {
          'role': 'assistant',
          'content': [
            {
              'type': 'text',
              'text': text,
            },
          ],
          'interruptedPartialRecovery': true,
        },
    };
  }

  Future<void> _upsertAssistantFailureMessage({
    required int groupId,
    required int? assistantMessageId,
    required String text,
  }) async {
    if (assistantMessageId == null) {
      await _insertAssistantStatusMessage(
        groupId: groupId,
        text: text,
        status: MessageStatus.failed,
      );
      return;
    }

    if (!_shouldProjectAssistantFailure(assistantMessageId)) {
      return;
    }
    await _updateAssistantStatusMessage(
      assistantMessageId: assistantMessageId,
      text: text,
      status: MessageStatus.failed,
    );
  }

  Future<void> _upsertAssistantCancelledMessage({
    required int groupId,
    required int? assistantMessageId,
    required String text,
  }) async {
    final currentMessage = assistantMessageId == null
        ? null
        : _findMessageById(assistantMessageId);
    if (currentMessage != null &&
        currentMessage.contentType == MessageContentType.plainText &&
        currentMessage.text.trim().isEmpty) {
      await _updateAssistantStatusMessage(
        assistantMessageId: assistantMessageId!,
        text: text,
        status: MessageStatus.interrupted,
      );
      return;
    }

    await _insertAssistantStatusMessage(
      groupId: groupId,
      text: text,
      status: MessageStatus.interrupted,
    );
  }

  void _syncAssistantFailureState({
    required int groupId,
    required int? assistantMessageId,
    required Object rawError,
  }) {
    final failureText = _formatSendFailureText(rawError);

    if (assistantMessageId == null) {
      unawaited(
        _insertAssistantStatusMessage(
          groupId: groupId,
          text: failureText,
          status: MessageStatus.failed,
        ),
      );
      return;
    }

    if (!_shouldProjectAssistantFailure(assistantMessageId)) {
      return;
    }
    unawaited(
      _updateAssistantStatusMessage(
        assistantMessageId: assistantMessageId,
        text: failureText,
        status: MessageStatus.failed,
      ),
    );
  }

  bool _shouldProjectAssistantFailure(int assistantMessageId) {
    final message = _findMessageById(assistantMessageId);
    if (message == null) {
      return true;
    }

    return switch (message.status) {
      MessageStatus.initial || MessageStatus.generating => true,
      MessageStatus.completed ||
      MessageStatus.interrupted ||
      MessageStatus.failed =>
        false,
    };
  }

  bool _hasVisibleInterruptedAssistantText(int? assistantMessageId) {
    if (assistantMessageId == null) {
      return false;
    }

    final message = _findMessageById(assistantMessageId);
    return message != null &&
        message.status == MessageStatus.interrupted &&
        message.text.trim().isNotEmpty;
  }

  String? _resolveLatestRuntimePreviewResponseText() {
    // Read straight from the preview state rather than from the timeline
    // projection: once per-entity preview takeover dedup hides preview blocks
    // whose truth counterpart has landed, the projection alone can no longer
    // surface the streamed text we need for interruption recovery.
    final previewState = _ref.read(runtimeStreamingPreviewStateProvider);
    for (final message in previewState.messages.reversed) {
      for (final block in message.blocks.reversed) {
        if (block.blockType != StreamingContentBlockType.text) {
          continue;
        }
        final text = block.text.trim();
        if (text.isEmpty) {
          continue;
        }
        return block.text;
      }
    }
    return null;
  }

  Future<void> _insertAssistantStatusMessage({
    required int groupId,
    required String text,
    required MessageStatus status,
  }) async {
    final message = ChatMessage(
      text: text,
      role: MessageRole.assistant,
      status: status,
    );
    final messageId = await _ref.read(databaseProvider).insertMessage(
          message,
          groupId,
        );
    message.id = messageId;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  Future<void> _updateAssistantStatusMessage({
    required int assistantMessageId,
    required String text,
    required MessageStatus status,
  }) async {
    _ref.read(messagesProvider.notifier).updateMessage(
          assistantMessageId,
          text,
        );
    _ref.read(messagesProvider.notifier).updateMessageStatus(
          assistantMessageId,
          status,
        );
    await _ref.read(databaseProvider).updateMessage(assistantMessageId, text);
    await _ref
        .read(databaseProvider)
        .updateMessageStatus(assistantMessageId, status);
  }

  ChatMessage? _findMessageById(int messageId) {
    return _ref
        .read(messagesProvider)
        .where((candidate) => candidate.id == messageId)
        .firstOrNull;
  }

  ChatMessage? _resolveLatestActiveToolMessageInCurrentTurn() {
    final messages = _ref.read(messagesProvider);
    final lastUserIndex = messages.lastIndexWhere((message) => message.isUser);
    final currentTurnMessages =
        lastUserIndex == -1 ? messages : messages.sublist(lastUserIndex + 1);

    for (final message in currentTurnMessages.reversed) {
      if (!message.isAssistant) {
        continue;
      }
      if (message.contentType != MessageContentType.toolInvocation &&
          message.contentType != MessageContentType.actionConfirmation) {
        continue;
      }
      final payload = message.payloadJson;
      if (payload == null) {
        continue;
      }
      ToolInvocation invocation;
      try {
        invocation = ToolInvocation.fromJson(payload);
      } catch (_) {
        continue;
      }
      if (invocation.status == ToolInvocationStatus.awaitingConfirmation ||
          invocation.status == ToolInvocationStatus.running) {
        return message;
      }
    }

    return null;
  }

  Future<void> _markToolMessageCancelled(ChatMessage message) async {
    final messageId = message.id;
    final payload = message.payloadJson;
    if (messageId == null || payload == null) {
      return;
    }

    final cancelledPayload = {
      ...payload,
      'status': ToolInvocationStatus.cancelled.name,
    };
    final cancelledMessage = message.copyWith(
      text: '已取消工具执行',
      payloadJson: cancelledPayload,
    );
    _ref.read(messagesProvider.notifier).replaceMessage(cancelledMessage);
    await _ref.read(databaseProvider).updateStructuredMessage(
          messageId,
          text: cancelledMessage.text,
          status: cancelledMessage.status,
          contentType: cancelledMessage.contentType,
          payloadJson: jsonEncode(cancelledPayload),
        );
  }

  String _cancelledTurnSummaryText() {
    return '已停止本轮回答。你可以继续提问，或让我基于当前结果继续整理。';
  }

  String _formatSendFailureText(Object error) {
    final rawMessage = error.toString().trim();
    final compactMessage = rawMessage
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^发送消息失败:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    if (compactMessage.isEmpty) {
      return '发送失败，请稍后重试。';
    }
    return '发送失败：$compactMessage';
  }

  Future<String?> _validateAttachmentSupport({
    required List<ChatAttachment> attachments,
    required ChatGroup currentGroup,
    required BaseLLM llm,
    required bool allowUnsupportedImageInputAttempt,
  }) async {
    if (attachments.isEmpty) {
      return null;
    }

    if (allowUnsupportedImageInputAttempt) {
      Logger.runtime(
        _tag,
        'attachment support overridden by user confirmation',
      );
      return null;
    }

    final runtimeSupport = await _resolveRuntimeSelectedModelImageSupport();
    if (runtimeSupport != null) {
      Logger.runtime(
        _tag,
        'attachment support resolved from runtime model capability',
        data: {
          'supportsImageInput': runtimeSupport,
        },
      );
      return runtimeSupport ? null : '当前模型不支持图片输入，请切换到支持多模态图片输入的模型后重试。';
    }

    final explicitSupport = llm.config['supportsImageInput'];
    if (explicitSupport is bool) {
      Logger.runtime(
        _tag,
        'attachment support resolved from llm.config',
        data: {
          'supportsImageInput': explicitSupport,
        },
      );
      return explicitSupport ? null : '当前模型不支持图片输入，请切换到支持多模态图片输入的模型后重试。';
    }

    final selectedModelSupport = await _resolveSelectedModelImageSupport();
    if (selectedModelSupport != null) {
      Logger.runtime(
        _tag,
        'attachment support resolved from selected model capability',
        data: {
          'supportsImageInput': selectedModelSupport,
        },
      );
      return selectedModelSupport ? null : '当前模型不支持图片输入，请切换到支持多模态图片输入的模型后重试。';
    }

    return null;
  }

  Future<bool?> _resolveSelectedModelImageSupport() async {
    try {
      final runtime = _ref.read(currentSessionRuntimeConfigProvider);
      if (runtime == null) {
        return null;
      }
      final config =
          await _ref.read(sessionLlmConfigResolverProvider).resolve(runtime);
      final raw =
          config.additionalConfig['llm.selected_model_supports_image_input'];
      if (raw is bool) {
        return raw;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool?> _resolveRuntimeSelectedModelImageSupport() async {
    try {
      final runtime = _ref.read(currentSessionRuntimeConfigProvider);
      if (runtime == null) {
        return null;
      }
      final config =
          await _ref.read(sessionLlmConfigResolverProvider).resolve(runtime);
      final raw = config
          .additionalConfig['llm.runtime_selected_model_supports_image_input'];
      if (raw is bool) {
        return raw;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _recordRuntimeImageInputSupportSuccessIfNeeded(
    List<ChatAttachment> attachments,
  ) async {
    if (attachments.isEmpty) {
      return;
    }
    try {
      final repository = _ref.read(appSettingsRepositoryProvider);
      final runtime = _ref.read(currentSessionRuntimeConfigProvider);
      final providerId = runtime?.providerId;
      final modelId = runtime?.modelId;
      if (providerId == null || modelId == null) {
        return;
      }
      await repository.saveRuntimeImageInputSupport(
        providerId: providerId,
        modelId: modelId,
        supportsImageInput: true,
      );
      Logger.runtime(
        _tag,
        'recorded runtime image support success',
        data: {
          'providerId': providerId,
          'modelId': modelId,
        },
      );
    } catch (error) {
      Logger.w(
        _tag,
        'failed to record runtime image support success: $error',
      );
    }
  }

  String _formatTurnFailureText(ChatTurn turn) {
    switch (turn.errorMessage) {
      case 'max_iterations_reached':
        return '本轮已达到工具探索上限，已停止继续执行。当前收集到了一些中间结果，但模型还没来得及整理出最终答复。你可以让我基于现有结果继续总结，或缩小问题范围后再试一次。';
      case 'max_tool_calls_reached':
        return '本轮已达到工具调用上限，已停止继续执行。当前保留了部分中间结果，但还没有整理成最终答复。你可以让我基于现有结果继续总结，或把问题范围收窄一些再试。';
      case 'max_duration_reached':
        return '本轮工具执行耗时过长，已自动停止。当前保留了部分中间结果，但还没有形成最终答复。你可以稍后重试，或缩小任务范围后继续。';
      case 'planner_no_terminal_decision':
        return '这轮工具执行已经结束，但模型没有产出最终答复，所以我先停在这里。你可以让我基于当前结果继续总结，或换一种更聚焦的问法再试一次。';
      default:
        final code = turn.errorMessage?.trim();
        if (code == null || code.isEmpty) {
          return '这轮工具执行未能正常完成，已停止继续执行。你可以稍后重试，或把问题说得更具体一些。';
        }
        return '这轮工具执行未能正常完成，已停止继续执行。失败原因：$code。你可以稍后重试，或调整问题后继续。';
    }
  }

  @override
  Future<void> cancelToolInvocation(ChatMessage message) async {
    if (message.id == null) {
      return;
    }

    final payload = message.payloadJson;
    final traceRecorder = _ref.read(traceRecorderProvider);
    final traceTurnId = _resolveTraceTurnId(payload, traceRecorder);
    final toolName = payload == null ? null : payload['toolName'] as String?;
    final agentTurnId = payload == null ? null : payload['agentTurnId'] as int?;

    final cancelledMessage = message.copyWith(
      text: '已取消工具执行',
      contentType: MessageContentType.plainText,
      payloadJson: null,
    );
    _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
    _ref.read(messagesProvider.notifier).replaceMessage(cancelledMessage);

    final dbHelper = _ref.read(databaseProvider);
    await dbHelper.updateStructuredMessage(
      message.id!,
      text: cancelledMessage.text,
      status: cancelledMessage.status,
      contentType: cancelledMessage.contentType,
      payloadJson: null,
    );
    if (agentTurnId != null) {
      final turnRepository = ChatTurnRepository(dbHelper);
      await turnRepository.markCancelled(
        agentTurnId,
        stopReason: 'cancelled_by_user',
      );
    }

    traceRecorder.record(
      turnId: traceTurnId,
      stage: ChatTraceStage.toolConfirmationAction,
      status: ChatTraceStatus.success,
      summary: '用户取消工具执行',
      data: {
        'action': 'cancel',
        'messageId': message.id,
        if (toolName != null) 'toolName': toolName,
      },
    );
  }

  @override
  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {
    final latestMessage = _resolveLatestMessageById(message);
    final effectiveMessage = latestMessage ?? message;
    final payload = effectiveMessage.payloadJson;
    final currentGroup = _ref.read(currentGroupProvider);
    if (effectiveMessage.id == null ||
        payload == null ||
        currentGroup?.id == null) {
      return;
    }

    final invocation = ToolInvocation.fromJson(payload);
    if (invocation.status != ToolInvocationStatus.awaitingConfirmation ||
        !invocation.requiresConfirmation) {
      Logger.w(
        _tag,
        'ignore stale tool confirmation tap messageId=${effectiveMessage.id} tool=${invocation.toolName} status=${invocation.status.name}',
      );
      return;
    }

    _ref
        .read(chatSendStateProvider.notifier)
        .setPhase(ChatSendPhase.executingTool);
    final traceRecorder = _ref.read(traceRecorderProvider);
    final traceTurnId = _resolveTraceTurnId(payload, traceRecorder);
    final agentTurnId = payload['agentTurnId'] as int?;
    traceRecorder.record(
      turnId: traceTurnId,
      stage: ChatTraceStage.toolConfirmationAction,
      status: ChatTraceStatus.success,
      summary: '用户确认继续执行工具',
      data: {
        'action': 'confirm',
        'messageId': effectiveMessage.id,
        'toolName': invocation.toolName,
        'trustTool': trustTool,
      },
    );
    if (agentTurnId != null) {
      await _resumeAgentLoopConfirmation(
        turnId: agentTurnId,
        invocation: invocation,
        traceTurnId: traceTurnId,
        trustTool: trustTool,
        sourceMessage: effectiveMessage,
      );
      return;
    }
    _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
  }

  @override
  Future<void> submitQuestionAnswers(
    ChatMessage message, {
    required AskUserQuestionResponse response,
  }) async {
    final payload = message.payloadJson;
    final currentGroup = _ref.read(currentGroupProvider);
    if (message.id == null || payload == null || currentGroup?.id == null) {
      return;
    }
    final turnId = payload['agentTurnId'] as int?;
    if (turnId == null) {
      return;
    }
    final request = AskUserQuestionRequest.fromJson(payload);
    final harness = _ref.read(turnHarnessProvider);
    if (harness == null) {
      return;
    }
    final traceRecorder = _ref.read(traceRecorderProvider);
    final traceTurnId = _resolveTraceTurnId(payload, traceRecorder);
    final dbHelper = _ref.read(databaseProvider);
    final currentGroupId = currentGroup!.id!;
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.preparing,
          clearStatusText: true,
        );
    final processor = _buildQuestionResumeProcessor(
      groupId: currentGroupId,
      traceTurnId: traceTurnId,
      turnId: turnId,
      sourceMessage: message,
      response: response,
      dbHelper: dbHelper,
    );
    await _runResumedAgentLoop(
      groupId: currentGroupId,
      turnId: turnId,
      processor: processor,
      stream: harness.resumeAfterQuestionAnswered(
        turnId: turnId,
        request: request,
        response: response,
        config: await _buildChatConfig(),
      ),
      onFinally: () async {
        _setIdleUnlessAwaitingConfirmation();
      },
    );
  }

  Future<void> _resumeAgentLoopConfirmation({
    required int turnId,
    required ToolInvocation invocation,
    required String traceTurnId,
    required bool trustTool,
    required ChatMessage sourceMessage,
  }) async {
    final harness = _ref.read(turnHarnessProvider);
    final currentGroup = _ref.read(currentGroupProvider);
    final currentGroupId = currentGroup?.id;
    final sourceMessageId = sourceMessage.id;
    if (harness == null || currentGroupId == null || sourceMessageId == null) {
      return;
    }

    final dbHelper = _ref.read(databaseProvider);
    final processor = _buildConfirmationResumeProcessor(
      groupId: currentGroupId,
      traceTurnId: traceTurnId,
      turnId: turnId,
      invocation: invocation,
      sourceMessage: sourceMessage,
      sourceMessageId: sourceMessageId,
      dbHelper: dbHelper,
    );

    await _runResumedAgentLoop(
      groupId: currentGroupId,
      turnId: turnId,
      processor: processor,
      stream: harness.resumeAfterConfirmation(
        turnId: turnId,
        invocation: invocation,
        config: await _buildChatConfig(),
        trustTool: trustTool,
      ),
      onFinally: () async {
        _settleSendPhaseFromProcessor(processor);
      },
    );
  }

  AgentEventProcessor _buildQuestionResumeProcessor({
    required int groupId,
    required String traceTurnId,
    required int turnId,
    required ChatMessage sourceMessage,
    required AskUserQuestionResponse response,
    required dynamic dbHelper,
  }) {
    return AgentEventProcessor(
      ref: _ref,
      groupId: groupId,
      traceTurnId: traceTurnId,
      agentTurnId: turnId,
      hooks: AgentEventHooks(
        onUserInteractionResult: (event) async {
          final resultMessage = sourceMessage.copyWith(
            text: event.content ?? sourceMessage.text,
            contentType: MessageContentType.askUserQuestionResult,
            payloadJson: {
              'type': 'result',
              ...?sourceMessage.payloadJson,
              'submittedAnswers': response.toJson(),
              'status': 'submitted',
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          await _replaceStructuredMessage(
            messageId: sourceMessage.id!,
            message: resultMessage,
            dbHelper: dbHelper,
          );
          return true;
        },
      ),
    );
  }

  AgentEventProcessor _buildConfirmationResumeProcessor({
    required int groupId,
    required String traceTurnId,
    required int turnId,
    required ToolInvocation invocation,
    required ChatMessage sourceMessage,
    required int sourceMessageId,
    required dynamic dbHelper,
  }) {
    var firstToolExecutionConsumed = false;
    return AgentEventProcessor(
      ref: _ref,
      groupId: groupId,
      traceTurnId: traceTurnId,
      agentTurnId: turnId,
      hooks: AgentEventHooks(
        transformFirstToolExecution: (event) async {
          if (firstToolExecutionConsumed) {
            return false;
          }
          firstToolExecutionConsumed = true;
          final runningPayload = {
            ...?event.payloadJson,
            'agentTurnId': turnId,
            traceTurnIdPayloadKey: traceTurnId,
          };
          final runningMessage = sourceMessage.copyWith(
            text: event.content ?? invocation.summary,
            contentType: MessageContentType.toolInvocation,
            payloadJson: runningPayload,
          );
          await _replaceStructuredMessage(
            messageId: sourceMessageId,
            message: runningMessage,
            dbHelper: dbHelper,
          );
          return true;
        },
      ),
    );
  }

  Future<void> _runResumedAgentLoop({
    required int groupId,
    required int turnId,
    required AgentEventProcessor processor,
    required Stream<ChatEvent> stream,
    Future<void> Function()? onFinally,
  }) async {
    _ref.read(chatSendStateProvider.notifier).setStatusText(null);
    await _runAgentEventStream(
      stream: stream,
      processor: processor,
      onError: (error, stackTrace, completion) {
        if (!completion.isCompleted) {
          completion.completeError(error, stackTrace);
        }
      },
      onSuccess: () async {
        await _finalizeTurnOutcome(
          groupId: groupId,
          turnId: turnId,
          processor: processor,
        );
      },
      onFinally: onFinally,
    );
  }

  Future<void> _replaceStructuredMessage({
    required int messageId,
    required ChatMessage message,
    required dynamic dbHelper,
  }) async {
    _ref.read(messagesProvider.notifier).replaceMessage(message);
    await dbHelper.updateStructuredMessage(
      messageId,
      text: message.text,
      status: message.status,
      contentType: message.contentType,
      payloadJson: jsonEncode(message.payloadJson),
    );
  }

  void _setIdleUnlessAwaitingConfirmation() {
    final sendState = _ref.read(chatSendStateProvider);
    if (!sendState.isGenerating &&
        sendState.phase != ChatSendPhase.awaitingConfirmation) {
      _ref.read(chatSendStateProvider.notifier).update(
            phase: ChatSendPhase.idle,
            clearStatusText: true,
          );
    }
  }

  void _settleSendPhaseFromProcessor(AgentEventProcessor processor) {
    final phase = processor.hasPendingConfirmation
        ? ChatSendPhase.awaitingConfirmation
        : ChatSendPhase.idle;
    _ref.read(chatSendStateProvider.notifier).update(
          phase: phase,
          clearStatusText: phase == ChatSendPhase.idle,
        );
  }

  String _resolveTraceTurnId(
    Map<String, dynamic>? payload,
    ChatTraceRecorder traceRecorder,
  ) {
    final rawTurnId = payload?[traceTurnIdPayloadKey];
    if (rawTurnId is String && rawTurnId.isNotEmpty) {
      return rawTurnId;
    }
    return traceRecorder.newTurnId();
  }

  void _recordPersistentPlannerTrace({
    required ChatTraceRecorder recorder,
    required PlannerRequestTraceEvent event,
    required ChatTraceStage stage,
    required ChatTraceStatus status,
    required String summary,
    required Map<String, dynamic> details,
  }) {
    unawaited(
      _resolvePersistentTraceTurnId(event.turnId).then((traceTurnId) {
        recorder.record(
          turnId: traceTurnId,
          stage: stage,
          status: status,
          summary: summary,
          data: details,
          timestamp: event.timestamp,
        );
      }),
    );
  }

  Future<String> _resolvePersistentTraceTurnId(int agentTurnId) async {
    final turn =
        await _ref.read(chatTurnRepositoryProvider).getTurn(agentTurnId);
    return _readTraceTurnIdFromTurn(turn) ?? 'turn_$agentTurnId';
  }

  String? _readTraceTurnIdFromTurn(ChatTurn? turn) {
    final runtimeContext =
        turn?.providerStateJson?[SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return null;
    }
    final raw = runtimeContext[traceTurnIdRuntimeContextKey];
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  ChatMessage? _resolveLatestMessageById(ChatMessage message) {
    final messageId = message.id;
    if (messageId == null) {
      return null;
    }
    final messages = _ref.read(messagesProvider);
    for (final candidate in messages) {
      if (candidate.id == messageId) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _loadGroups() async {
    try {
      final dbHelper = _ref.read(databaseProvider);
      final groups = await dbHelper.getAllGroups();
      _ref.read(groupsProvider.notifier).setGroups(groups);
    } catch (e) {
      Logger.e(_tag, '加载分组失败', e);
    }
  }
}

class _HandledSendFailure implements Exception {
  final Object error;

  const _HandledSendFailure(this.error);

  @override
  String toString() => error.toString();
}

class _PreparedOutboundUserMessage {
  const _PreparedOutboundUserMessage({
    required this.request,
    required this.text,
    required this.userMessage,
  });

  final SendMessageRequest request;
  final String text;
  final ChatMessage userMessage;
}

List<SendMessageRequest> _flattenSendRequests(SendMessageRequest request) {
  return <SendMessageRequest>[
    SendMessageRequest(
      text: request.text,
      attachments: request.attachments,
      allowUnsupportedImageInputAttempt:
          request.allowUnsupportedImageInputAttempt,
      dispatchMode: request.dispatchMode,
    ),
    ...request.additionalStartMessages.expand(_flattenSendRequests),
  ];
}
