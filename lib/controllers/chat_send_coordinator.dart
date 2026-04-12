import 'dart:convert';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_send/chat_send_drafts.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    _ref.read(focusNodeProvider).unfocus();
    Logger.d(
      _tag,
      '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...',
    );

    cancelActiveStream();
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

    _ref.read(autoScrollToBottomProvider.notifier).state = true;

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

    final sendDraft = buildChatSendTransactionDraft(
      text: text,
      currentMessages: List<ChatMessage>.from(_ref.read(messagesProvider)),
    );
    final userMessage = sendDraft.userMessage;

    _ref.read(messagesProvider.notifier).addMessage(userMessage);
    await Future.delayed(const Duration(milliseconds: 1));

    final aiMessage = sendDraft.assistantPlaceholder;

    try {
      final dbHelper = _ref.read(databaseProvider);
      final currentGroupId = _ref.read(currentGroupProvider)!.id!;

      Logger.d(_tag, '保存用户消息到数据库...');
      final userMessageId =
          await dbHelper.insertMessage(userMessage, currentGroupId);
      userMessage.id = userMessageId;

      final historyMessages = sendDraft.historyMessages;

      Logger.d(_tag, '开始接收AI响应流，有效对话对数量: ${historyMessages.length / 2}');

      final chatService = _ref.read(chatServiceProvider);
      final toolPreparationResult = await chatService.prepareToolAssistance(
        groupId: currentGroupId,
        userMessage: text,
        history: historyMessages,
        turnId: turnId,
      );
      Logger.i(
        _tag,
        '工具预处理结果: invocation=${toolPreparationResult.toolInvocation?.toolName ?? 'none'}, '
        'invocationStatus=${toolPreparationResult.toolInvocation?.status.name ?? 'none'}, '
        'hasToolResult=${toolPreparationResult.toolResult != null}, '
        'extraContext=${toolPreparationResult.additionalContextMessages.length}',
      );
      final toolPreparationDraft = resolveToolPreparationDraft(
        historyMessages: historyMessages,
        toolPreparationResult: toolPreparationResult,
      );
      final toolContextHistory = toolPreparationDraft.toolContextHistory;

      if (toolPreparationDraft.requiresConfirmation) {
        _ref
            .read(chatSendStateProvider.notifier)
            .setPhase(toolPreparationDraft.nextPhase);
        final confirmationMessage = ChatMessage(
          text: toolPreparationResult.toolInvocation!.summary,
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.actionConfirmation,
          payloadJson: {
            ...toolPreparationResult.toolInvocation!.toJson(),
            traceTurnIdPayloadKey: turnId,
          },
        );
        final confirmationMessageId =
            await dbHelper.insertMessage(confirmationMessage, currentGroupId);
        confirmationMessage.id = confirmationMessageId;
        _ref.read(messagesProvider.notifier).addMessage(confirmationMessage);
        traceRecorder.record(
          turnId: turnId,
          stage: ChatTraceStage.sendDone,
          status: ChatTraceStatus.success,
          summary: '发送进入确认态',
          data: {
            'phase': ChatSendPhase.awaitingConfirmation.name,
            'toolName': toolPreparationResult.toolInvocation!.toolName,
          },
        );
        return;
      }

      if (toolPreparationResult.toolResult != null) {
        final toolMessage = ChatMessage(
          text: toolPreparationResult.toolResult!.displayText,
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.toolResult,
          payloadJson: toolPreparationResult.toolResult!.toJson(),
        );
        final toolMessageId =
            await dbHelper.insertMessage(toolMessage, currentGroupId);
        toolMessage.id = toolMessageId;
        _ref.read(messagesProvider.notifier).addMessage(toolMessage);
      }

      Logger.d(_tag, '创建AI消息占位...');
      final aiMessageId = await dbHelper.insertMessage(aiMessage, currentGroupId);
      aiMessage.id = aiMessageId;
      _ref.read(messagesProvider.notifier).addMessage(aiMessage);

      _ref.read(chatSendStateProvider.notifier).update(
            isGenerating: true,
            phase: toolPreparationDraft.nextPhase,
          );

      final systemPrompt = _ref.read(systemPromptProvider) ?? "";
      final useReasoning = _ref.read(useReasoningProvider);

      final subscription = chatService
          .sendMessageStream(
        text,
        toolContextHistory,
        ChatConfig(useReasoning: useReasoning, systemPrompt: systemPrompt),
        turnId: turnId,
      )
          .listen(
        (content) async {
          final delta = resolveStreamingAssistantDelta(content);
          switch (delta.kind) {
            case StreamingAssistantDeltaKind.content:
              Logger.d(_tag, '收到AI响应片段: ${delta.content}');
              _ref
                  .read(messagesProvider.notifier)
                  .appendToMessage(aiMessageId, delta.content);
              await dbHelper.updateMessage(aiMessageId, aiMessage.text);
              break;
            case StreamingAssistantDeltaKind.reasoning:
              Logger.d(_tag, '收到推理内容: ${delta.content}');
              _ref
                  .read(messagesProvider.notifier)
                  .appendReasoningToMessage(aiMessageId, delta.content);
              await dbHelper.updateMessageReasoning(
                  aiMessageId, aiMessage.reasoningContent);
              break;
            case StreamingAssistantDeltaKind.ignored:
              Logger.d(_tag, '忽略无法识别的流式响应片段');
              break;
          }
        },
        onError: (error) {
          Logger.e(_tag, 'AI响应出错', error);
          final failureDraft = resolveStreamingAssistantFailureDraft(
            assistantMessageId: aiMessageId,
            error: error,
          );
          if (failureDraft.shouldPersistStatusUpdate) {
            _ref
                .read(messagesProvider.notifier)
                .updateMessageStatus(aiMessageId, failureDraft.nextStatus);
            dbHelper.updateMessageStatus(aiMessageId, failureDraft.nextStatus);
          }
          if (failureDraft.shouldStopGenerating) {
            _ref.read(chatSendStateProvider.notifier).setGenerating(false);
          }
          if (failureDraft.shouldSetIdlePhase) {
            _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
          }
          final traceEntry = failureDraft.traceEntry;
          if (traceEntry != null) {
            traceRecorder.record(
              turnId: turnId,
              stage: traceEntry.stage,
              status: traceEntry.status,
              summary: traceEntry.summary,
              data: traceEntry.data,
            );
          }
        },
        onDone: () {
          Logger.i(_tag, 'AI响应完成');
          final latestAssistantMessage = _findMessageById(aiMessageId) ?? aiMessage;
          final completionDraft = resolveStreamingAssistantCompletionDraft(
            assistantMessageId: aiMessageId,
            assistantMessage: latestAssistantMessage,
          );
          if (completionDraft.shouldPersistStatusUpdate) {
            _ref
                .read(messagesProvider.notifier)
                .updateMessageStatus(aiMessageId, completionDraft.nextStatus);
            dbHelper.updateMessageStatus(aiMessageId, completionDraft.nextStatus);
          }
          if (completionDraft.shouldStopGenerating) {
            _ref.read(chatSendStateProvider.notifier).setGenerating(false);
          }
          if (completionDraft.shouldSetIdlePhase) {
            _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
          }
          final traceEntry = completionDraft.traceEntry;
          if (traceEntry != null) {
            traceRecorder.record(
              turnId: turnId,
              stage: traceEntry.stage,
              status: traceEntry.status,
              summary: traceEntry.summary,
              data: traceEntry.data,
            );
          }
          if (completionDraft.shouldScheduleAutoSummary) {
            scheduleAutoSummary();
          }
        },
        cancelOnError: true,
      );

      _ref.read(streamSubscriptionProvider.notifier).state = subscription;
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息过程中出错', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      traceRecorder.record(
        turnId: turnId,
        stage: ChatTraceStage.sendFailed,
        status: ChatTraceStatus.failure,
        summary: '发送消息过程中出错',
        data: {
          'error': e.toString(),
        },
      );
      if (aiMessage.id != null) {
        _ref
            .read(messagesProvider.notifier)
            .updateMessageStatus(aiMessage.id!, MessageStatus.failed);
      }
      _ref.read(chatSendStateProvider.notifier).update(
            isGenerating: false,
            phase: ChatSendPhase.idle,
          );

      final dbHelper = _ref.read(databaseProvider);
      if (aiMessage.id != null) {
        dbHelper.updateMessageStatus(aiMessage.id!, MessageStatus.failed);
      }
    }
  }

  ChatMessage? _findMessageById(int id) {
    for (final message in _ref.read(messagesProvider)) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
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
    final payload = message.payloadJson;
    final currentGroup = _ref.read(currentGroupProvider);
    if (message.id == null || payload == null || currentGroup?.id == null) {
      return;
    }

    _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.executingTool);
    final traceRecorder = _ref.read(traceRecorderProvider);
    final traceTurnId = _resolveTraceTurnId(payload, traceRecorder);
    final invocation = ToolInvocation.fromJson(payload);
    traceRecorder.record(
      turnId: traceTurnId,
      stage: ChatTraceStage.toolConfirmationAction,
      status: ChatTraceStatus.success,
      summary: '用户确认继续执行工具',
      data: {
        'action': 'confirm',
        'messageId': message.id,
        'toolName': invocation.toolName,
        'trustTool': trustTool,
      },
    );
    final executionResult = await _ref.read(chatServiceProvider).executeToolInvocation(
          groupId: currentGroup!.id!,
          invocation: invocation,
          trustTool: trustTool,
          turnId: traceTurnId,
        );
    final executionDraft = resolveConfirmedToolExecutionDraft(
      sourceMessage: message,
      invocation: invocation,
      executionResult: executionResult,
    );
    final runningMessage = executionDraft.runningMessage;
    _ref.read(messagesProvider.notifier).replaceMessage(runningMessage);

    final dbHelper = _ref.read(databaseProvider);
    await dbHelper.updateStructuredMessage(
      message.id!,
      text: runningMessage.text,
      status: runningMessage.status,
      contentType: runningMessage.contentType,
      payloadJson: jsonEncode(runningMessage.payloadJson),
    );

    final toolMessage = executionDraft.toolResultMessage;
    if (toolMessage == null) {
      _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
      return;
    }

    final toolMessageId =
        await dbHelper.insertMessage(toolMessage, currentGroup.id!);
    toolMessage.id = toolMessageId;
    _ref.read(messagesProvider.notifier).addMessage(toolMessage);
    _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
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
