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
import 'package:ai_chat/services/assistant_stream_output_buffer.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/storage/chat_storage.dart';
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

      Logger.d(_tag, '保存用户消息到数据库...');
      final userMessageId =
          await dbHelper.insertMessage(userMessage, currentGroupId);
      userMessage.id = userMessageId;

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
    }
  }

  Future<void> _sendMessageWithAgentLoop({
    required String text,
    required int currentGroupId,
    required ChatMessage userMessage,
    required String turnId,
    required TurnHarness harness,
    required VoidCallback scheduleAutoSummary,
  }) async {
    final dbHelper = _ref.read(databaseProvider);
    final traceRecorder = _ref.read(traceRecorderProvider);
    final turnRepository = ChatTurnRepository(dbHelper);
    final createdTurn = ChatTurn(
      groupId: currentGroupId,
      status: ChatTurnStatus.running,
      userInput: text,
    );
    final turnRecordId = await turnRepository.createTurn(createdTurn);
    final persistedTurn = createdTurn.copyWith(id: turnRecordId);
    final config = ChatConfig(
      useReasoning: _ref.read(useReasoningProvider),
      systemPrompt: _ref.read(systemPromptProvider) ?? '',
      userSystemPrompt: _ref.read(systemPromptProvider) ?? '',
    );

    int? assistantMessageId;
    ChatMessage? assistantMessage;
    AssistantStreamOutputBuffer? assistantStreamBuffer;
    final completion = Completer<void>();

    final subscription = harness
        .runTurn(
      turn: persistedTurn,
      config: config,
    )
        .asyncMap((event) async {
      switch (event.eventType) {
        case ChatEventType.userMessage:
          return;
        case ChatEventType.assistantPlannerMessage:
          final plannerMessage = ChatMessage(
            text: event.content ?? '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            payloadJson: event.payloadJson,
          );
          final plannerMessageId =
              await dbHelper.insertMessage(plannerMessage, currentGroupId);
          plannerMessage.id = plannerMessageId;
          _ref.read(messagesProvider.notifier).addMessage(plannerMessage);
          break;
        case ChatEventType.assistantToolCall:
          final message = ChatMessage(
            text: event.content ?? '准备执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolInvocation,
            payloadJson: event.payloadJson,
          );
          final messageId = await dbHelper.insertMessage(message, currentGroupId);
          message.id = messageId;
          _ref.read(messagesProvider.notifier).addMessage(message);
          break;
        case ChatEventType.assistantToolConfirmation:
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.awaitingConfirmation,
              );
          final payloadJson = {
            ...?event.payloadJson,
            'status': ToolInvocationStatus.awaitingConfirmation.name,
            'summary': event.content ?? '准备执行工具',
            'requiresConfirmation': true,
            'agentTurnId': turnRecordId,
            traceTurnIdPayloadKey: turnId,
          };
          final message = ChatMessage(
            text: event.content ?? '准备执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: payloadJson,
          );
          final messageId = await dbHelper.insertMessage(message, currentGroupId);
          message.id = messageId;
          _ref.read(messagesProvider.notifier).addMessage(message);
          traceRecorder.record(
            turnId: turnId,
            stage: ChatTraceStage.sendDone,
            status: ChatTraceStatus.success,
            summary: '发送进入确认态',
            data: {
              'phase': ChatSendPhase.awaitingConfirmation.name,
              'toolName': payloadJson['toolName'],
            },
          );
          break;
        case ChatEventType.assistantQuestionPrompt:
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.idle,
              );
          final promptMessage = ChatMessage(
            text: event.content ?? '请先回答几个问题',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.askUserQuestionPrompt,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnRecordId,
              traceTurnIdPayloadKey: turnId,
            },
          );
          final promptMessageId =
              await dbHelper.insertMessage(promptMessage, currentGroupId);
          promptMessage.id = promptMessageId;
          _ref.read(messagesProvider.notifier).addMessage(promptMessage);
          break;
        case ChatEventType.toolExecutionStarted:
          _ref.read(chatSendStateProvider.notifier).setPhase(
                ChatSendPhase.executingTool,
              );
          final message = ChatMessage(
            text: event.content ?? '正在执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolInvocation,
            payloadJson: event.payloadJson,
          );
          final messageId = await dbHelper.insertMessage(message, currentGroupId);
          message.id = messageId;
          _ref.read(messagesProvider.notifier).addMessage(message);
          break;
        case ChatEventType.toolResult:
          final message = ChatMessage(
            text: event.content ?? '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolResult,
            payloadJson: event.payloadJson,
          );
          final messageId = await dbHelper.insertMessage(message, currentGroupId);
          message.id = messageId;
          _ref.read(messagesProvider.notifier).addMessage(message);
          break;
        case ChatEventType.userInteractionResult:
          final resultMessage = ChatMessage(
            text: event.content ?? '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.askUserQuestionResult,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnRecordId,
              traceTurnIdPayloadKey: turnId,
            },
          );
          final resultMessageId =
              await dbHelper.insertMessage(resultMessage, currentGroupId);
          resultMessage.id = resultMessageId;
          _ref.read(messagesProvider.notifier).addMessage(resultMessage);
          break;
        case ChatEventType.toolError:
          await _appendToolResultMessage(
            dbHelper: dbHelper,
            groupId: currentGroupId,
            event: event,
            fallbackText: '工具执行失败',
            payloadJson: _buildToolFailurePayload(event),
          );
          break;
        case ChatEventType.assistantTextDelta:
          if (assistantMessageId == null) {
            final placeholder = ChatMessage(
              text: '',
              role: MessageRole.assistant,
              status: MessageStatus.generating,
            );
            assistantMessageId =
                await dbHelper.insertMessage(placeholder, currentGroupId);
            placeholder.id = assistantMessageId;
            assistantMessage = placeholder;
            _ref.read(messagesProvider.notifier).addMessage(placeholder);
          }
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: true,
                phase: ChatSendPhase.streamingResponse,
              );
          final activeAssistantMessageId =
              assistantMessageId ?? (throw StateError('missing assistant message id'));
          final activeAssistantMessage =
              assistantMessage ?? (throw StateError('missing assistant message'));
          assistantStreamBuffer ??= _createAssistantStreamBuffer(
            messageId: activeAssistantMessageId,
            message: activeAssistantMessage,
            dbHelper: dbHelper,
          );
          assistantStreamBuffer!.onDelta(event.content ?? '');
          break;
        case ChatEventType.assistantTextFinal:
          break;
        case ChatEventType.finalAnswer:
          if (assistantMessageId == null) {
            final message = ChatMessage(
              text: event.content ?? '',
              role: MessageRole.assistant,
              status: MessageStatus.completed,
            );
            assistantMessageId =
                await dbHelper.insertMessage(message, currentGroupId);
            message.id = assistantMessageId;
            assistantMessage = message;
            _ref.read(messagesProvider.notifier).addMessage(message);
          } else {
            await _finalizeAssistantText(
              buffer: assistantStreamBuffer,
              messageId: assistantMessageId!,
              message: assistantMessage,
              dbHelper: dbHelper,
              fallbackText: event.content ?? assistantMessage?.text ?? '',
              explicitText: event.content,
            );
            _ref
                .read(messagesProvider.notifier)
                .updateMessageStatus(assistantMessageId!, MessageStatus.completed);
            await dbHelper.updateMessageStatus(
              assistantMessageId!,
              MessageStatus.completed,
            );
          }
          assistantStreamBuffer?.dispose();
          assistantStreamBuffer = null;
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.idle,
              );
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
          break;
        case ChatEventType.turnStatus:
        case ChatEventType.error:
        case ChatEventType.assistantReasoningDelta:
          break;
      }
    }).listen(
      (_) {},
      onError: (error, stackTrace) {
        unawaited(assistantStreamBuffer?.cancel());
        assistantStreamBuffer?.dispose();
        assistantStreamBuffer = null;
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
          assistantMessageId: assistantMessageId,
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
      onDone: () {
        if (!completion.isCompleted) {
          completion.complete();
        }
      },
      cancelOnError: true,
    );

    _ref.read(streamSubscriptionProvider.notifier).state = subscription;
    try {
      await completion.future;
    } finally {
      await assistantStreamBuffer?.cancel();
      assistantStreamBuffer?.dispose();
    }
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

    _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.executingTool);
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
    int? assistantMessageId;
    ChatMessage? assistantMessage;
    AssistantStreamOutputBuffer? assistantStreamBuffer;
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.preparing,
        );
    final completion = Completer<void>();
    final subscription = harness
        .resumeAfterQuestionAnswered(
          turnId: turnId,
          request: request,
          response: response,
          config: ChatConfig(
            useReasoning: _ref.read(useReasoningProvider),
            systemPrompt: _ref.read(systemPromptProvider) ?? '',
            userSystemPrompt: _ref.read(systemPromptProvider) ?? '',
          ),
        )
        .asyncMap((event) async {
      switch (event.eventType) {
        case ChatEventType.userInteractionResult:
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
          break;
        case ChatEventType.assistantPlannerMessage:
          final plannerMessage = ChatMessage(
            text: event.content ?? '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final plannerMessageId =
              await dbHelper.insertMessage(plannerMessage, currentGroupId);
          plannerMessage.id = plannerMessageId;
          _ref.read(messagesProvider.notifier).addMessage(plannerMessage);
          break;
        case ChatEventType.assistantQuestionPrompt:
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.idle,
              );
          break;
        case ChatEventType.assistantToolCall:
          final toolCallMessage = ChatMessage(
            text: event.content ?? '准备执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolInvocation,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final toolCallMessageId =
              await dbHelper.insertMessage(toolCallMessage, currentGroupId);
          toolCallMessage.id = toolCallMessageId;
          _ref.read(messagesProvider.notifier).addMessage(toolCallMessage);
          break;
        case ChatEventType.assistantToolConfirmation:
          final confirmationMessage = ChatMessage(
            text: event.content ?? '准备执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final confirmationMessageId =
              await dbHelper.insertMessage(confirmationMessage, currentGroupId);
          confirmationMessage.id = confirmationMessageId;
          _ref.read(messagesProvider.notifier).addMessage(confirmationMessage);
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.awaitingConfirmation,
              );
          break;
        case ChatEventType.toolExecutionStarted:
          _ref.read(chatSendStateProvider.notifier).setPhase(
                ChatSendPhase.executingTool,
              );
          final runningMessage = ChatMessage(
            text: event.content ?? '正在执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolInvocation,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final runningMessageId =
              await dbHelper.insertMessage(runningMessage, currentGroupId);
          runningMessage.id = runningMessageId;
          _ref.read(messagesProvider.notifier).addMessage(runningMessage);
          break;
        case ChatEventType.toolResult:
          await _appendToolResultMessage(
            dbHelper: dbHelper,
            groupId: currentGroupId,
            event: event,
            fallbackText: '',
            payloadJson: event.payloadJson,
          );
          break;
        case ChatEventType.assistantTextDelta:
          if (assistantMessageId == null) {
            final placeholder = ChatMessage(
              text: '',
              role: MessageRole.assistant,
              status: MessageStatus.generating,
            );
            assistantMessageId =
                await dbHelper.insertMessage(placeholder, currentGroupId);
            placeholder.id = assistantMessageId;
            assistantMessage = placeholder;
            _ref.read(messagesProvider.notifier).addMessage(placeholder);
          }
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: true,
                phase: ChatSendPhase.streamingResponse,
              );
          final activeAssistantMessageId =
              assistantMessageId ?? (throw StateError('missing assistant message id'));
          final activeAssistantMessage =
              assistantMessage ?? (throw StateError('missing assistant message'));
          assistantStreamBuffer ??= _createAssistantStreamBuffer(
            messageId: activeAssistantMessageId,
            message: activeAssistantMessage,
            dbHelper: dbHelper,
          );
          assistantStreamBuffer!.onDelta(event.content ?? '');
          break;
        case ChatEventType.finalAnswer:
          if (assistantMessageId == null) {
            final finalMessage = ChatMessage(
              text: event.content ?? '',
              role: MessageRole.assistant,
              status: MessageStatus.completed,
            );
            assistantMessageId =
                await dbHelper.insertMessage(finalMessage, currentGroupId);
            finalMessage.id = assistantMessageId;
            assistantMessage = finalMessage;
            _ref.read(messagesProvider.notifier).addMessage(finalMessage);
          } else {
            final completedAssistantMessageId =
                assistantMessageId ?? (throw StateError('missing assistant message id'));
            await _finalizeAssistantText(
              buffer: assistantStreamBuffer,
              messageId: completedAssistantMessageId,
              message: assistantMessage,
              dbHelper: dbHelper,
              fallbackText: event.content ?? assistantMessage?.text ?? '',
              explicitText: event.content,
            );
            _ref.read(messagesProvider.notifier).updateMessageStatus(
                  completedAssistantMessageId,
                  MessageStatus.completed,
                );
            await dbHelper.updateMessageStatus(
              completedAssistantMessageId,
              MessageStatus.completed,
            );
          }
          assistantStreamBuffer?.dispose();
          assistantStreamBuffer = null;
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.idle,
              );
          break;
        case ChatEventType.toolError:
          await _appendToolResultMessage(
            dbHelper: dbHelper,
            groupId: currentGroupId,
            event: event,
            fallbackText: '工具执行失败',
            payloadJson: _buildToolFailurePayload(event),
          );
          break;
        case ChatEventType.assistantTextFinal:
        case ChatEventType.userMessage:
        case ChatEventType.assistantReasoningDelta:
        case ChatEventType.turnStatus:
        case ChatEventType.error:
          break;
      }
    }).listen(
      (_) {},
      onError: (error, stackTrace) {
        unawaited(assistantStreamBuffer?.cancel());
        assistantStreamBuffer?.dispose();
        assistantStreamBuffer = null;
        _ref.read(chatSendStateProvider.notifier).update(
              isGenerating: false,
              phase: ChatSendPhase.idle,
            );
        if (!completion.isCompleted) {
          completion.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completion.isCompleted) {
          completion.complete();
        }
      },
      cancelOnError: true,
    );

    _ref.read(streamSubscriptionProvider.notifier).state = subscription;
    try {
      await completion.future;
    } finally {
      await assistantStreamBuffer?.cancel();
      assistantStreamBuffer?.dispose();
      if (identical(_ref.read(streamSubscriptionProvider), subscription)) {
        _ref.read(streamSubscriptionProvider.notifier).state = null;
      }
      final sendState = _ref.read(chatSendStateProvider);
      if (!sendState.isGenerating &&
          sendState.phase != ChatSendPhase.awaitingConfirmation) {
        _ref.read(chatSendStateProvider.notifier).setPhase(ChatSendPhase.idle);
      }
    }
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
    int? assistantMessageId;
    ChatMessage? assistantMessage;
    AssistantStreamOutputBuffer? assistantStreamBuffer;
    var hasPendingConfirmation = false;

    await for (final event in harness.resumeAfterConfirmation(
      turnId: turnId,
      invocation: invocation,
      config: ChatConfig(
        useReasoning: _ref.read(useReasoningProvider),
        systemPrompt: _ref.read(systemPromptProvider) ?? '',
        userSystemPrompt: _ref.read(systemPromptProvider) ?? '',
      ),
      trustTool: trustTool,
    )) {
      switch (event.eventType) {
        case ChatEventType.toolExecutionStarted:
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
          break;
        case ChatEventType.assistantToolCall:
          final toolCallMessage = ChatMessage(
            text: event.content ?? '准备执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.toolInvocation,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final toolCallMessageId =
              await dbHelper.insertMessage(toolCallMessage, currentGroupId);
          toolCallMessage.id = toolCallMessageId;
          _ref.read(messagesProvider.notifier).addMessage(toolCallMessage);
          break;
        case ChatEventType.assistantPlannerMessage:
          final plannerMessage = ChatMessage(
            text: event.content ?? '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final plannerMessageId =
              await dbHelper.insertMessage(plannerMessage, currentGroupId);
          plannerMessage.id = plannerMessageId;
          _ref.read(messagesProvider.notifier).addMessage(plannerMessage);
          break;
        case ChatEventType.assistantToolConfirmation:
          hasPendingConfirmation = true;
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.awaitingConfirmation,
              );
          final confirmationPayload = {
            ...?event.payloadJson,
            'status': ToolInvocationStatus.awaitingConfirmation.name,
            'summary': event.content ?? '准备执行工具',
            'requiresConfirmation': true,
            'agentTurnId': turnId,
            traceTurnIdPayloadKey: traceTurnId,
          };
          final confirmationMessage = ChatMessage(
            text: event.content ?? '准备执行工具',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: confirmationPayload,
          );
          final confirmationMessageId =
              await dbHelper.insertMessage(confirmationMessage, currentGroupId);
          confirmationMessage.id = confirmationMessageId;
          _ref.read(messagesProvider.notifier).addMessage(confirmationMessage);
          break;
        case ChatEventType.assistantQuestionPrompt:
          _ref.read(chatSendStateProvider.notifier).update(
                isGenerating: false,
                phase: ChatSendPhase.idle,
              );
          final promptMessage = ChatMessage(
            text: event.content ?? '请先回答几个问题',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.askUserQuestionPrompt,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final promptMessageId =
              await dbHelper.insertMessage(promptMessage, currentGroupId);
          promptMessage.id = promptMessageId;
          _ref.read(messagesProvider.notifier).addMessage(promptMessage);
          break;
        case ChatEventType.toolResult:
          await _appendToolResultMessage(
            dbHelper: dbHelper,
            groupId: currentGroupId,
            event: event,
            fallbackText: '',
            payloadJson: event.payloadJson,
          );
          break;
        case ChatEventType.userInteractionResult:
          final resultMessage = ChatMessage(
            text: event.content ?? '',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.askUserQuestionResult,
            payloadJson: {
              ...?event.payloadJson,
              'agentTurnId': turnId,
              traceTurnIdPayloadKey: traceTurnId,
            },
          );
          final resultMessageId =
              await dbHelper.insertMessage(resultMessage, currentGroupId);
          resultMessage.id = resultMessageId;
          _ref.read(messagesProvider.notifier).addMessage(resultMessage);
          break;
        case ChatEventType.assistantTextDelta:
          if (assistantMessageId == null) {
            final placeholder = ChatMessage(
              text: '',
              role: MessageRole.assistant,
              status: MessageStatus.generating,
            );
            assistantMessageId =
                await dbHelper.insertMessage(placeholder, currentGroupId);
            placeholder.id = assistantMessageId;
            assistantMessage = placeholder;
            _ref.read(messagesProvider.notifier).addMessage(placeholder);
          }
          final activeAssistantMessageId = assistantMessageId;
          final activeAssistantMessage =
              assistantMessage ?? (throw StateError('missing assistant message'));
          assistantStreamBuffer ??= _createAssistantStreamBuffer(
            messageId: activeAssistantMessageId,
            message: activeAssistantMessage,
            dbHelper: dbHelper,
          );
          assistantStreamBuffer.onDelta(event.content ?? '');
          break;
        case ChatEventType.finalAnswer:
          if (assistantMessageId == null) {
            final finalMessage = ChatMessage(
              text: event.content ?? '',
              role: MessageRole.assistant,
              status: MessageStatus.completed,
            );
            assistantMessageId =
                await dbHelper.insertMessage(finalMessage, currentGroupId);
            finalMessage.id = assistantMessageId;
            assistantMessage = finalMessage;
            _ref.read(messagesProvider.notifier).addMessage(finalMessage);
          } else {
            final completedAssistantMessageId = assistantMessageId;
            await _finalizeAssistantText(
              buffer: assistantStreamBuffer,
              messageId: completedAssistantMessageId,
              message: assistantMessage,
              dbHelper: dbHelper,
              fallbackText: event.content ?? assistantMessage?.text ?? '',
              explicitText: event.content,
            );
            _ref
                .read(messagesProvider.notifier)
                .updateMessageStatus(completedAssistantMessageId, MessageStatus.completed);
            await dbHelper.updateMessageStatus(
              completedAssistantMessageId,
              MessageStatus.completed,
            );
          }
          assistantStreamBuffer?.dispose();
          assistantStreamBuffer = null;
          break;
        case ChatEventType.toolError:
          await _appendToolResultMessage(
            dbHelper: dbHelper,
            groupId: currentGroupId,
            event: event,
            fallbackText: '工具执行失败',
            payloadJson: _buildToolFailurePayload(event),
          );
          break;
        case ChatEventType.assistantTextFinal:
        case ChatEventType.userMessage:
        case ChatEventType.assistantReasoningDelta:
        case ChatEventType.turnStatus:
        case ChatEventType.error:
          break;
      }
    }

    await assistantStreamBuffer?.cancel();
    assistantStreamBuffer?.dispose();

    _ref.read(chatSendStateProvider.notifier).setPhase(
      hasPendingConfirmation
          ? ChatSendPhase.awaitingConfirmation
          : ChatSendPhase.idle,
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

  Future<void> _appendToolResultMessage({
    required ChatStorage dbHelper,
    required int groupId,
    required ChatEvent event,
    required String fallbackText,
    required Map<String, dynamic>? payloadJson,
  }) async {
    final message = ChatMessage(
      text: event.content ?? fallbackText,
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      contentType: MessageContentType.toolResult,
      payloadJson: payloadJson,
    );
    final messageId = await dbHelper.insertMessage(message, groupId);
    message.id = messageId;
    _ref.read(messagesProvider.notifier).addMessage(message);
  }

  AssistantStreamOutputBuffer _createAssistantStreamBuffer({
    required int messageId,
    required ChatMessage message,
    required ChatStorage dbHelper,
  }) {
    return AssistantStreamOutputBuffer(
      onUiFlush: (text) {
        message.text = text;
        _ref.read(messagesProvider.notifier).updateMessage(messageId, text);
      },
      onPersistFlush: (text) async {
        message.text = text;
        await dbHelper.updateMessage(messageId, text);
      },
      uiFlushInterval: const Duration(milliseconds: 16),
    );
  }

  Future<String> _finalizeAssistantText({
    required AssistantStreamOutputBuffer? buffer,
    required int messageId,
    required ChatMessage? message,
    required ChatStorage dbHelper,
    required String fallbackText,
    String? explicitText,
  }) async {
    await buffer?.finish();
    final finalText = explicitText ?? buffer?.fullText ?? fallbackText;
    if (message != null && message.text != finalText) {
      message.text = finalText;
      _ref.read(messagesProvider.notifier).updateMessage(messageId, finalText);
      await dbHelper.updateMessage(messageId, finalText);
    }
    return finalText;
  }

  Map<String, dynamic> _buildToolFailurePayload(ChatEvent event) {
    return {
      ...?event.payloadJson,
      'status': event.payloadJson?['status'] ?? 'failure',
      'errorMessage':
          event.payloadJson?['errorMessage'] ?? event.status ?? 'unknown_error',
    };
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
