import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/skill/invoked_skill_context.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/debug/streaming_trace_recorder.dart';
import 'package:ai_chat/services/session_runtime_marker_service.dart';
import 'package:ai_chat/services/skills/explicit_skill_invocation_parser.dart';
import 'package:ai_chat/services/skills/invoked_skill_reminder_builder.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_event_processor.dart';

const String traceTurnIdPayloadKey = 'traceTurnId';

abstract class ChatSendCoordinator {
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
    if (text.trim().isEmpty) return;

    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup == null) return;
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
      },
    );

    if (currentGroup.id == null) {
      try {
        final dbHelper = _ref.read(databaseProvider);
        final newGroup = currentGroup.copyWith(title: text);
        final groupId = await dbHelper.insertGroup(newGroup);
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
    final explicitSkill = await explicitSkillParser.parse(text);
    final sanitizedText = explicitSkill.cleanedUserText.trim().isEmpty
        ? text
        : explicitSkill.cleanedUserText;

    final userMessage = ChatMessage(
      text: sanitizedText,
      role: MessageRole.user,
      status: MessageStatus.completed,
    );

    _ref.read(messagesProvider.notifier).addMessage(userMessage);
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

      Logger.d(_tag, '保存用户消息到数据库...');
      final userMessageId =
          await dbHelper.insertMessage(userMessage, currentGroupId);
      userMessage.id = userMessageId;

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
        text: sanitizedText,
        currentGroupId: currentGroupId,
        userMessage: userMessage,
        turnId: turnId,
        harness: turnHarness,
        runtimeMarkerPreparation: runtimeMarkerPreparation,
        runtimeMarkerService: runtimeMarkerService,
        explicitInvokedSkill: explicitSkill.invokedSkill,
        scheduleAutoSummary: scheduleAutoSummary,
      );
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
    required ChatMessage userMessage,
    required String turnId,
    required TurnHarness harness,
    required SessionRuntimeMarkerPreparation runtimeMarkerPreparation,
    required SessionRuntimeMarkerService runtimeMarkerService,
    required InvokedSkillContext? explicitInvokedSkill,
    required VoidCallback scheduleAutoSummary,
  }) async {
    final dbHelper = _ref.read(databaseProvider);
    final traceRecorder = _ref.read(traceRecorderProvider);
    final turnRepository = ChatTurnRepository(dbHelper);
    final createdTurn = ChatTurn(
      groupId: currentGroupId,
      status: ChatTurnStatus.running,
      userInput: text,
      providerStateJson: _buildTurnRuntimeContext(
        runtimeMarkerService: runtimeMarkerService,
        runtimeMarkerPreparation: runtimeMarkerPreparation,
        explicitInvokedSkill: explicitInvokedSkill,
      ),
    );
    final turnRecordId = await turnRepository.createTurn(createdTurn);
    final persistedTurn = createdTurn.copyWith(id: turnRecordId);
    _ref.read(streamingTraceRecorderProvider.notifier).recordStage(
          traceId: streamingTraceIdForTurn(turnRecordId),
          turnId: turnRecordId.toString(),
          stage: StreamingTraceStage.turnStarted,
          timestamp: userMessage.timestamp,
          details: {
            'userMessagePreview': text.substring(0, text.length.clamp(0, 80)),
          },
        );
    await runtimeMarkerService.persistInjectedDate(
      groupId: currentGroupId,
      currentDate: runtimeMarkerPreparation.currentDate,
    );
    final config = _buildChatConfig();

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
  }) {
    final context = runtimeMarkerService.buildTurnRuntimeContext(
      runtimeMarkerPreparation,
    );
    if (explicitInvokedSkill == null) {
      return context;
    }
    final reminder = const InvokedSkillReminderBuilder().build(explicitInvokedSkill);
    final runtimeContext =
        Map<String, dynamic>.from(context[SessionRuntimeMarkerService.runtimeContextKey] as Map);
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

  ChatConfig _buildChatConfig() {
    return ChatConfig(
      systemPrompt: '',
      userSystemPrompt: _ref.read(systemPromptProvider) ?? '',
    );
  }

  Future<void> _finalizeTurnOutcome({
    required int groupId,
    required int turnId,
    required AgentEventProcessor processor,
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
      await _upsertAssistantFailureMessage(
        groupId: groupId,
        assistantMessageId: processor.assistantMessageId,
        text: _formatTurnFailureText(turn),
      );
    }

    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.idle,
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
        config: _buildChatConfig(),
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
        config: _buildChatConfig(),
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
