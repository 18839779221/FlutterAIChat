import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/session_runtime_marker_service.dart';
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
    _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.preparing);
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

    final userMessage = ChatMessage(
      text: text,
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
        text: text,
        currentGroupId: currentGroupId,
        userMessage: userMessage,
        turnId: turnId,
        harness: turnHarness,
        runtimeMarkerPreparation: runtimeMarkerPreparation,
        runtimeMarkerService: runtimeMarkerService,
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
    required VoidCallback scheduleAutoSummary,
  }) async {
    final dbHelper = _ref.read(databaseProvider);
    final traceRecorder = _ref.read(traceRecorderProvider);
    final turnRepository = ChatTurnRepository(dbHelper);
    final createdTurn = ChatTurn(
      groupId: currentGroupId,
      status: ChatTurnStatus.running,
      userInput: text,
      providerStateJson: runtimeMarkerService.buildTurnRuntimeContext(
        runtimeMarkerPreparation,
      ),
    );
    final turnRecordId = await turnRepository.createTurn(createdTurn);
    final persistedTurn = createdTurn.copyWith(id: turnRecordId);
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

  Future<void> _appendVisibleSendFailureMessage({
    required int? groupId,
    required Object error,
  }) async {
    if (groupId == null) {
      return;
    }

    final failureMessage = ChatMessage(
      text: _formatSendFailureText(error),
      role: MessageRole.assistant,
      status: MessageStatus.failed,
    );
    final dbHelper = _ref.read(databaseProvider);
    final messageId = await dbHelper.insertMessage(failureMessage, groupId);
    failureMessage.id = messageId;
    _ref.read(messagesProvider.notifier).addMessage(failureMessage);
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
      systemPrompt: _ref.read(systemPromptProvider) ?? '',
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
    final dbHelper = _ref.read(databaseProvider);
    if (assistantMessageId == null) {
      final failureMessage = ChatMessage(
        text: text,
        role: MessageRole.assistant,
        status: MessageStatus.failed,
      );
      final messageId = await dbHelper.insertMessage(failureMessage, groupId);
      failureMessage.id = messageId;
      _ref.read(messagesProvider.notifier).addMessage(failureMessage);
      return;
    }

    if (!_shouldProjectAssistantFailure(assistantMessageId)) {
      return;
    }

    _ref.read(messagesProvider.notifier).updateMessage(
          assistantMessageId,
          text,
        );
    _ref.read(messagesProvider.notifier).updateMessageStatus(
          assistantMessageId,
          MessageStatus.failed,
        );
    await dbHelper.updateMessage(assistantMessageId, text);
    await dbHelper.updateMessageStatus(
        assistantMessageId, MessageStatus.failed);
  }

  Future<void> _upsertAssistantCancelledMessage({
    required int groupId,
    required int? assistantMessageId,
    required String text,
  }) async {
    final dbHelper = _ref.read(databaseProvider);
    final currentMessage = assistantMessageId == null
        ? null
        : _ref
            .read(messagesProvider)
            .where((candidate) => candidate.id == assistantMessageId)
            .firstOrNull;
    if (currentMessage != null &&
        currentMessage.contentType == MessageContentType.plainText &&
        currentMessage.text.trim().isEmpty) {
      final resolvedAssistantMessageId = assistantMessageId!;
      _ref.read(messagesProvider.notifier).updateMessage(
            resolvedAssistantMessageId,
            text,
          );
      _ref.read(messagesProvider.notifier).updateMessageStatus(
            resolvedAssistantMessageId,
            MessageStatus.interrupted,
          );
      await dbHelper.updateMessage(resolvedAssistantMessageId, text);
      await dbHelper.updateMessageStatus(
        resolvedAssistantMessageId,
        MessageStatus.interrupted,
      );
      return;
    }

    final cancelledMessage = ChatMessage(
      text: text,
      role: MessageRole.assistant,
      status: MessageStatus.interrupted,
    );
    final messageId = await dbHelper.insertMessage(cancelledMessage, groupId);
    cancelledMessage.id = messageId;
    _ref.read(messagesProvider.notifier).addMessage(cancelledMessage);
  }

  void _syncAssistantFailureState({
    required int groupId,
    required int? assistantMessageId,
    required Object rawError,
  }) {
    final dbHelper = _ref.read(databaseProvider);
    final failureText = _formatSendFailureText(rawError);

    if (assistantMessageId == null) {
      final failureMessage = ChatMessage(
        text: failureText,
        role: MessageRole.assistant,
        status: MessageStatus.failed,
      );
      dbHelper.insertMessage(failureMessage, groupId).then((messageId) {
        failureMessage.id = messageId;
        _ref.read(messagesProvider.notifier).addMessage(failureMessage);
      });
      return;
    }

    if (!_shouldProjectAssistantFailure(assistantMessageId)) {
      return;
    }

    _ref.read(messagesProvider.notifier).updateMessage(
          assistantMessageId,
          failureText,
        );
    _ref.read(messagesProvider.notifier).updateMessageStatus(
          assistantMessageId,
          MessageStatus.failed,
        );
    dbHelper.updateMessage(assistantMessageId, failureText);
    dbHelper.updateMessageStatus(assistantMessageId, MessageStatus.failed);
  }

  bool _shouldProjectAssistantFailure(int assistantMessageId) {
    final message = _ref
        .read(messagesProvider)
        .where((candidate) => candidate.id == assistantMessageId)
        .firstOrNull;
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

    final message = _ref
        .read(messagesProvider)
        .where((candidate) => candidate.id == assistantMessageId)
        .firstOrNull;
    return message != null &&
        message.status == MessageStatus.interrupted &&
        message.text.trim().isNotEmpty;
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
        );
    final processor = AgentEventProcessor(
      ref: _ref,
      groupId: currentGroupId,
      traceTurnId: traceTurnId,
      agentTurnId: turnId,
      hooks: AgentEventHooks(
        onUserInteractionResult: (event) async {
          final resultMessage = message.copyWith(
            text: event.content ?? message.text,
            contentType: MessageContentType.askUserQuestionResult,
            payloadJson: {
              'type': 'result',
              ...?message.payloadJson,
              'submittedAnswers': response.toJson(),
              'status': 'submitted',
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          _ref.read(messagesProvider.notifier).replaceMessage(resultMessage);
          await dbHelper.updateStructuredMessage(
            message.id!,
            text: resultMessage.text,
            status: resultMessage.status,
            contentType: resultMessage.contentType,
            payloadJson: jsonEncode(resultMessage.payloadJson),
          );
          return true;
        },
      ),
    );
    await _runAgentEventStream(
      stream: harness.resumeAfterQuestionAnswered(
        turnId: turnId,
        request: request,
        response: response,
        config: _buildChatConfig(),
      ),
      processor: processor,
      onError: (error, stackTrace, completion) {
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.idle,
            );
        if (!completion.isCompleted) {
          completion.completeError(error, stackTrace);
        }
      },
      onSuccess: () async {
        await _finalizeTurnOutcome(
          groupId: currentGroupId,
          turnId: turnId,
          processor: processor,
        );
      },
      onFinally: () async {
        final sendState = _ref.read(chatSendStateProvider);
        if (!sendState.isGenerating &&
            sendState.phase != ChatSendPhase.awaitingConfirmation) {
          _ref
              .read(chatSendStateProvider.notifier)
              .setPhase(ChatSendPhase.idle);
        }
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
    var firstToolExecutionConsumed = false;

    final processor = AgentEventProcessor(
      ref: _ref,
      groupId: currentGroupId,
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
          _ref.read(messagesProvider.notifier).replaceMessage(runningMessage);
          await dbHelper.updateStructuredMessage(
            sourceMessageId,
            text: runningMessage.text,
            status: runningMessage.status,
            contentType: runningMessage.contentType,
            payloadJson: jsonEncode(runningPayload),
          );
          return true;
        },
      ),
    );

    await _runAgentEventStream(
      stream: harness.resumeAfterConfirmation(
        turnId: turnId,
        invocation: invocation,
        config: _buildChatConfig(),
        trustTool: trustTool,
      ),
      processor: processor,
      onError: (error, stackTrace, completion) {
        if (!completion.isCompleted) {
          completion.completeError(error, stackTrace);
        }
      },
      onSuccess: () async {
        await _finalizeTurnOutcome(
          groupId: currentGroupId,
          turnId: turnId,
          processor: processor,
        );
      },
      onFinally: () async {
        _ref.read(chatSendStateProvider.notifier).setPhase(
              processor.hasPendingConfirmation
                  ? ChatSendPhase.awaitingConfirmation
                  : ChatSendPhase.idle,
            );
      },
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
