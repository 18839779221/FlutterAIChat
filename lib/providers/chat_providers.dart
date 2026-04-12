import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_chat/models/chat_send/chat_send_drafts.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import '../models/chat_message.dart';
import '../models/chat/tool_workflow_step.dart';
import '../models/chat_group.dart';
import '../models/response/message_content_type.dart';
import '../models/trace/chat_trace_event.dart';
import '../models/tool/tool_invocation.dart';
import '../repositories/app_settings_repository.dart';
import '../services/chat_service.dart';
import '../services/chat_trace_recorder.dart';
import '../storage/chat_storage.dart';
import '../utils/logger.dart';

// 数据库提供者（实际实现在 main.dart 中通过 override 注入）
final databaseProvider = Provider<ChatStorage>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 databaseProvider');
});

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 AppSettingsRepository');
});

final traceRecorderProvider = Provider<ChatTraceRecorder>((ref) {
  return ChatTraceRecorder();
});

// 聊天服务提供者
final chatServiceProvider = Provider<ChatService>((ref) {
  return ref.watch(chatServiceFactoryProvider);
});

// 聊天服务工厂提供者
final chatServiceFactoryProvider = Provider<ChatService>((ref) {
  throw UnimplementedError("需要在 main.dart 中覆盖创建 ChatService 的代码");
});

// 消息列表提供者
final messagesProvider =
    StateNotifierProvider<MessagesNotifier, List<ChatMessage>>((ref) {
  return MessagesNotifier(ref);
});

class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;

  MessagesNotifier(this._ref) : super([]);

  void setMessages(List<ChatMessage> messages) {
    final sortedMessages = [...messages]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    state = sortedMessages;
  }

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void insertMessages(int index, List<ChatMessage> messages) {
    final newList = [...state];
    newList.insertAll(index, messages);
    state = newList;
  }

  void updateMessage(int id, String text) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index];
      message.text = text;
      state = [...state];
    }
  }

  void appendToMessage(int id, String text) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index];
      message.appendText(text);
      state = [...state]; // 触发状态更新
    }
  }

  void appendReasoningToMessage(int id, String reasoning) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index];
      message.appendReasoning(reasoning);
      state = [...state]; // 触发状态更新
    }
  }

  void updateMessageStatus(int id, MessageStatus status) {
    final index = state.indexWhere((message) => message.id == id);
    if (index != -1) {
      final message = state[index].copyWith(status: status);
      final newList = [...state];
      newList[index] = message;
      state = newList;
    }
  }

  void replaceMessage(ChatMessage updatedMessage) {
    final index =
        state.indexWhere((message) => message.id == updatedMessage.id);
    if (index == -1) {
      return;
    }

    final newList = [...state];
    newList[index] = updatedMessage;
    state = newList;
  }

  void deleteMessagePair(int index) {
    final newList = [...state];
    final indexMessage = newList[index];
    ChatMessage? userMessage, aiMessage;

    if (indexMessage.isUser) {
      userMessage = newList[index];
      if (index < newList.length - 1) {
        aiMessage = newList[index + 1];
      }
    } else {
      aiMessage = newList[index];
      if (index > 0) {
        userMessage = newList[index - 1];
      }
    }

    if (userMessage != null && aiMessage != null) {
      newList.remove(aiMessage);
      newList.remove(userMessage);
      state = newList;

      // 从数据库中删除
      final dbHelper = _ref.read(databaseProvider);
      if (userMessage.id != null) {
        dbHelper.deleteMessage(userMessage.id!);
      }
      if (aiMessage.id != null) {
        dbHelper.deleteMessage(aiMessage.id!);
      }
    }
  }

  void clearMessages() {
    state = [];
  }
}

// 聊天分组提供者
final groupsProvider =
    StateNotifierProvider<GroupsNotifier, List<ChatGroup>>((ref) {
  return GroupsNotifier(ref);
});

class GroupsNotifier extends StateNotifier<List<ChatGroup>> {
  final Ref _ref;

  GroupsNotifier(this._ref) : super([]);

  void setGroups(List<ChatGroup> groups) {
    state = groups;
  }

  void addGroup(ChatGroup group) {
    state = [...state, group];
  }

  Future<void> deleteGroup(int id) async {
    final dbHelper = _ref.read(databaseProvider);
    await dbHelper.deleteGroup(id);
    state = state.where((group) => group.id != id).toList();

    // 如果删除的是当前分组，需要加载新的当前分组
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == id) {
      final latestGroup = await dbHelper.getLatestGroup();
      if (latestGroup != null) {
        _ref.read(currentGroupProvider.notifier).state = latestGroup;
      } else {
        // 创建新分组
        _ref.read(chatControllerProvider).createNewGroup();
      }
    }
  }
}

// 当前分组提供者
final currentGroupProvider = StateProvider<ChatGroup?>((ref) => null);

// 系统提示词提供者
final systemPromptProvider = StateProvider<String?>((ref) => null);

final toolWorkflowExpansionProvider = StateNotifierProvider<
    ToolWorkflowExpansionNotifier, Map<String, String>>((ref) {
  return ToolWorkflowExpansionNotifier();
});

class ToolWorkflowExpansionNotifier extends StateNotifier<Map<String, String>> {
  ToolWorkflowExpansionNotifier() : super(const {});

  void toggleExpandedStep({
    required String turnId,
    required String stepId,
  }) {
    final currentStepId = state[turnId];
    if (currentStepId == stepId) {
      final nextState = Map<String, String>.from(state)..remove(turnId);
      state = nextState;
      return;
    }

    state = {
      ...state,
      turnId: stepId,
    };
  }

  void clearTurn(String turnId) {
    if (!state.containsKey(turnId)) {
      return;
    }
    final nextState = Map<String, String>.from(state)..remove(turnId);
    state = nextState;
  }
}

String? resolveWorkflowExpandedStepId({
  required String turnId,
  required List<ToolWorkflowStep> steps,
  required String? manualExpandedStepId,
}) {
  for (final step in steps) {
    if (step.status == ToolWorkflowStepStatus.failed) {
      return step.stepId;
    }
  }

  for (final step in steps) {
    if (step.status == ToolWorkflowStepStatus.awaitingConfirmation ||
        step.status == ToolWorkflowStepStatus.running) {
      return step.stepId;
    }
  }

  if (manualExpandedStepId == null) {
    return null;
  }

  final matched = steps.where((step) => step.stepId == manualExpandedStepId);
  if (matched.isEmpty) {
    return null;
  }

  return manualExpandedStepId;
}

// 正在自动摘要状态提供者
final isAutoSummarizingProvider = StateProvider<bool>((ref) => false);

// 加载更多状态提供者
final isLoadingMoreProvider = StateProvider<bool>((ref) => false);

// 是否有更多消息提供者
final hasMoreMessagesProvider = StateProvider<bool>((ref) => true);

// 自动滚动提供者
final autoScrollToBottomProvider = StateProvider<bool>((ref) => true);

// 推理模式提供者
final useReasoningProvider = StateProvider<bool>((ref) => false);

// 简洁模式提供者
final useConciseModeProvider = StateProvider<bool>((ref) => false);

// 暂存的系统提示词提供者
final cachedSystemPromptProvider = StateProvider<String?>((ref) => null);

// 初始化状态提供者
final isInitializingProvider = StateProvider<bool>((ref) => true);

// 控制器提供者
final scrollControllerProvider = Provider<ScrollController>((ref) {
  final controller = ScrollController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

// 文本控制器提供者
final textControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

// 焦点提供者
final focusNodeProvider = Provider<FocusNode>((ref) {
  final focusNode = FocusNode();
  ref.onDispose(() => focusNode.dispose());
  return focusNode;
});

// 流订阅提供者
final streamSubscriptionProvider =
    StateProvider<StreamSubscription?>((ref) => null);

const String _traceTurnIdPayloadKey = 'traceTurnId';

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

final chatSendCoordinatorProvider = Provider<ChatSendCoordinator>((ref) {
  return DefaultChatSendCoordinator(ref);
});

abstract class ChatSessionCoordinator {
  Future<void> loadGroups();

  Future<void> loadCurrentGroup();

  Future<void> createNewGroup();

  Future<void> loadMessages();

  Future<void> loadMoreMessages();

  Future<void> selectGroup(ChatGroup group);
}

final chatSessionCoordinatorProvider = Provider<ChatSessionCoordinator>((ref) {
  return DefaultChatSessionCoordinator(ref);
});

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
            _traceTurnIdPayloadKey: turnId,
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
    final rawTurnId = payload?[_traceTurnIdPayloadKey];
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

class DefaultChatSessionCoordinator implements ChatSessionCoordinator {
  static const String _tag = 'ChatSessionCoordinator';
  static const int _pageSize = 20;

  final Ref _ref;

  DefaultChatSessionCoordinator(this._ref);

  @override
  Future<void> loadGroups() async {
    try {
      final dbHelper = _ref.read(databaseProvider);
      final groups = await dbHelper.getAllGroups();
      _ref.read(groupsProvider.notifier).setGroups(groups);
      await loadCurrentGroup();
    } catch (e) {
      Logger.e(_tag, '加载分组失败', e);
    }
  }

  @override
  Future<void> loadCurrentGroup() async {
    try {
      final dbHelper = _ref.read(databaseProvider);
      final latestGroup = await dbHelper.getLatestGroup();

      if (latestGroup != null) {
        final now = DateTime.now();
        final lastMessageTime = latestGroup.lastMessageAt;
        final isSameDay = now.year == lastMessageTime.year &&
            now.month == lastMessageTime.month &&
            now.day == lastMessageTime.day;
        final timeDiff = now.difference(lastMessageTime);

        if (!isSameDay && timeDiff.inHours >= 5) {
          await createNewGroup();
        } else {
          _ref.read(currentGroupProvider.notifier).state = latestGroup;
          _ref.read(systemPromptProvider.notifier).state =
              latestGroup.systemPrompt;
          await loadMessages();
        }
      } else {
        await createNewGroup();
      }
    } catch (e) {
      Logger.e(_tag, '加载当前分组失败', e);
    }
  }

  @override
  Future<void> createNewGroup() async {
    try {
      final groups = _ref.read(groupsProvider);
      final systemPrompt = _ref.read(systemPromptProvider);

      final newGroup = ChatGroup(
        title: '新对话 ${groups.length + 1}',
        systemPrompt: systemPrompt,
      );

      _ref.read(currentGroupProvider.notifier).state = newGroup;
      _ref.read(messagesProvider.notifier).clearMessages();
      _ref.read(hasMoreMessagesProvider.notifier).state = false;
      _ref.read(isInitializingProvider.notifier).state = false;
    } catch (e) {
      Logger.e(_tag, '创建新分组失败', e);
    }
  }

  @override
  Future<void> loadMessages() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return;

    try {
      Logger.d(_tag, '开始加载历史消息...');
      final dbHelper = _ref.read(databaseProvider);
      final messages = await dbHelper.getMessagesByGroup(currentGroup!.id!);
      final totalCount = await dbHelper.getGroupMessageCount(currentGroup.id!);

      _ref.read(messagesProvider.notifier).setMessages(messages);
      _ref.read(hasMoreMessagesProvider.notifier).state =
          totalCount > messages.length;
      _ref.read(isInitializingProvider.notifier).state = false;

      Logger.i(_tag, '成功加载 ${messages.length} 条历史消息');
    } catch (e) {
      Logger.e(_tag, '加载历史消息失败', e);
    }
  }

  @override
  Future<void> loadMoreMessages() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return;
    final groupId = currentGroup!.id!;

    if (_ref.read(isLoadingMoreProvider) ||
        !_ref.read(hasMoreMessagesProvider)) {
      return;
    }

    _ref.read(isLoadingMoreProvider.notifier).state = true;

    try {
      final dbHelper = _ref.read(databaseProvider);
      final currentCount = _ref.read(messagesProvider).length;
      final newMessages = await dbHelper.getMessagesByGroupWithPagination(
        groupId: groupId,
        limit: _pageSize,
        offset: currentCount,
      );

      if (newMessages.isEmpty) {
        _ref.read(hasMoreMessagesProvider.notifier).state = false;
        return;
      }

      _ref
          .read(messagesProvider.notifier)
          .insertMessages(currentCount, newMessages);
    } catch (e) {
      Logger.e(_tag, '加载更多消息失败', e);
    } finally {
      _ref.read(isLoadingMoreProvider.notifier).state = false;
    }
  }

  @override
  Future<void> selectGroup(ChatGroup group) async {
    _ref.read(currentGroupProvider.notifier).state = group;
    _ref.read(systemPromptProvider.notifier).state = group.systemPrompt;
    await loadMessages();
  }
}

// 聊天控制器提供者 - 集中处理业务逻辑
final chatControllerProvider =
    Provider<ChatController>((ref) => ChatController(ref));

class ChatController {
  static const String _tag = 'ChatController';

  // 自动摘要配置
  static const int _minMessagesForSummary = 6; // 最少6条消息（3对）
  static const int _inactivitySeconds = 30; // 30秒无活动

  final Ref _ref;
  Timer? _autoSummaryTimer;

  ChatController(this._ref) {
    _initScrollListener();
  }

  void _initScrollListener() {
    final scrollController = _ref.read(scrollControllerProvider);

    scrollController.addListener(() {
      // 加载更多逻辑
      if (scrollController.position.pixels <=
              scrollController.position.minScrollExtent + 100 &&
          !_ref.read(isLoadingMoreProvider)) {
        loadMoreMessages();
      }

      // 自动滚动逻辑
      if (_ref.read(isGeneratingProvider)) {
        if (scrollController.position.userScrollDirection ==
            ScrollDirection.reverse) {
          _ref.read(autoScrollToBottomProvider.notifier).state = false;
        }

        if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 10) {
          _ref.read(autoScrollToBottomProvider.notifier).state = true;
        }
      }
    });
  }

  // 加载分组
  Future<void> loadGroups() async {
    await _ref.read(chatSessionCoordinatorProvider).loadGroups();
  }

  // 加载当前分组
  Future<void> loadCurrentGroup() async {
    await _ref.read(chatSessionCoordinatorProvider).loadCurrentGroup();
  }

  // 创建新分组
  Future<void> createNewGroup() async {
    await _ref.read(chatSessionCoordinatorProvider).createNewGroup();
  }

  // 加载消息
  Future<void> loadMessages() async {
    await _ref.read(chatSessionCoordinatorProvider).loadMessages();
  }

  // 加载更多消息
  Future<void> loadMoreMessages() async {
    await _ref.read(chatSessionCoordinatorProvider).loadMoreMessages();
  }

  // 发送消息
  Future<void> sendMessage(String text) async {
    await _ref.read(chatSendCoordinatorProvider).sendMessage(
          text,
          scheduleAutoSummary: _scheduleAutoSummary,
          cancelActiveStream: cancelStreamSubscription,
        );
  }

  Future<void> cancelToolInvocation(ChatMessage message) async {
    await _ref.read(chatSendCoordinatorProvider).cancelToolInvocation(message);
  }

  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {
    await _ref.read(chatSendCoordinatorProvider).confirmToolInvocation(
          message,
          trustTool: trustTool,
        );
  }

  Future<void> structureMessageForDebug(ChatMessage message) async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) {
      return;
    }

    final isSupportedMessage = message.isAssistant &&
        message.status == MessageStatus.completed &&
        message.contentType == MessageContentType.plainText;
    if (!isSupportedMessage) {
      return;
    }

    final dbHelper = _ref.read(databaseProvider);
    final placeholderMessage = ChatMessage(
      text: '',
      role: MessageRole.assistant,
      status: MessageStatus.generating,
    );

    final placeholderId =
        await dbHelper.insertMessage(placeholderMessage, currentGroup!.id!);
    placeholderMessage.id = placeholderId;
    _ref.read(messagesProvider.notifier).addMessage(placeholderMessage);

    final result = await _ref
        .read(chatServiceProvider)
        .structureMessageForDebug(message.text);
    final completedMessage = result.isStructuredCard
        ? placeholderMessage.copyWith(
            text: result.card!.summary,
            status: MessageStatus.completed,
            contentType: MessageContentType.structuredCard,
            payloadJson: result.card!.toJson(),
          )
        : placeholderMessage.copyWith(
            text: result.fallbackText!,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
            payloadJson: null,
          );

    await dbHelper.updateStructuredMessage(
      placeholderId,
      text: completedMessage.text,
      status: completedMessage.status,
      contentType: completedMessage.contentType,
      payloadJson: completedMessage.payloadJson == null
          ? null
          : jsonEncode(completedMessage.payloadJson),
    );
    _ref.read(messagesProvider.notifier).replaceMessage(completedMessage);
  }

  // 取消流订阅
  void cancelStreamSubscription() {
    final subscription = _ref.read(streamSubscriptionProvider);
    if (subscription != null) {
      subscription.cancel();
      _ref.read(streamSubscriptionProvider.notifier).state = null;
    }

    if (!_ref.read(isGeneratingProvider)) return;
    _ref.read(chatSendStateProvider.notifier).update(
          isGenerating: false,
          phase: ChatSendPhase.idle,
        );

    final messages = _ref.read(messagesProvider);
    if (messages.isEmpty) return;

    final lastIndex =
        messages.lastIndexWhere((message) => message.role == MessageRole.assistant);
    if (lastIndex == -1) return;

    final aiMessage = messages[lastIndex];
    // 如果是主动取消（例如发送新消息），则标记为中断状态
    if (aiMessage.status == MessageStatus.generating) {
      _ref
          .read(messagesProvider.notifier)
          .updateMessageStatus(aiMessage.id!, MessageStatus.interrupted);

      final dbHelper = _ref.read(databaseProvider);
      if (aiMessage.id != null) {
        dbHelper.updateMessageStatus(aiMessage.id!, MessageStatus.interrupted);
      }
    }
  }

  // 设置系统提示词
  Future<void> setSystemPrompt(String? prompt) async {
    _ref.read(systemPromptProvider.notifier).state = prompt;

    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup != null && currentGroup.id != null) {
      final dbHelper = _ref.read(databaseProvider);
      await dbHelper.updateGroupSystemPrompt(currentGroup.id!, prompt);
    }
  }

  // 设置推理模式
  void setUseReasoning(bool value) {
    _ref.read(useReasoningProvider.notifier).state = value;
  }

  // 设置简洁模式
  void setUseConciseMode(bool value) {
    final currentPrompt = _ref.read(systemPromptProvider);
    final cachedPrompt = _ref.read(cachedSystemPromptProvider);

    if (value) {
      // 开启简洁模式
      if (cachedPrompt == null) {
        // 暂存当前prompt
        _ref.read(cachedSystemPromptProvider.notifier).state = currentPrompt;
      }
      // 设置简洁模式prompt
      setSystemPrompt("极简模式，只回答问题本身，无需任何解释背景和扩展，尽量控制在30字之内(特殊情况下允许超出)");
    } else {
      // 关闭简洁模式，恢复之前的prompt
      setSystemPrompt(cachedPrompt);
      _ref.read(cachedSystemPromptProvider.notifier).state = null;
    }

    _ref.read(useConciseModeProvider.notifier).state = value;
  }

  // 选择分组
  Future<void> selectGroup(ChatGroup group) async {
    await _ref.read(chatSessionCoordinatorProvider).selectGroup(group);
  }

  // 生成对话摘要并更新分组标题
  Future<String?> summarizeAndUpdateTitle() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return null;

    final messages = _ref.read(messagesProvider);
    if (messages.isEmpty) return null;

    try {
      Logger.i(_tag, '开始生成对话摘要...');

      // 只选择已完成的消息用于摘要
      final completedMessages = messages
          .where((msg) => msg.status == MessageStatus.completed)
          .toList()
          .reversed
          .toList();

      if (completedMessages.isEmpty) return null;

      final chatService = _ref.read(chatServiceProvider);
      final summary =
          await chatService.llm.summarizeConversation(completedMessages);

      // 更新数据库中的分组标题
      final dbHelper = _ref.read(databaseProvider);
      await dbHelper.updateGroupTitle(currentGroup!.id!, summary,
          isSummarized: true);

      // 更新当前分组状态
      _ref.read(currentGroupProvider.notifier).state =
          currentGroup.copyWith(title: summary, isSummarized: true);

      // 重新加载分组列表
      await loadGroups();

      Logger.i(_tag, '对话摘要生成成功: $summary');
      return summary;
    } catch (e) {
      Logger.e(_tag, '生成对话摘要失败', e);
      return null;
    }
  }

  // 调度自动摘要
  void _scheduleAutoSummary() {
    // 取消之前的定时器
    _autoSummaryTimer?.cancel();

    // 设置新的定时器
    _autoSummaryTimer = Timer(const Duration(seconds: _inactivitySeconds), () {
      _checkAndTriggerAutoSummary();
    });
  }

  // 检查并触发自动摘要
  Future<void> _checkAndTriggerAutoSummary() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return;

    // 检查是否已经摘要过
    if (currentGroup!.isSummarized) {
      Logger.d(_tag, '分组已经生成过摘要，跳过自动摘要');
      return;
    }

    // 检查是否正在生成或正在摘要
    if (_ref.read(isGeneratingProvider) ||
        _ref.read(isAutoSummarizingProvider)) {
      Logger.d(_tag, '正在生成消息或摘要中，跳过自动摘要');
      return;
    }

    // 检查标题是否为默认标题
    if (!_isDefaultTitle(currentGroup.title)) {
      Logger.d(_tag, '标题已自定义，跳过自动摘要');
      return;
    }

    final messages = _ref.read(messagesProvider);
    final completedMessages =
        messages.where((msg) => msg.status == MessageStatus.completed).toList();

    // 检查消息数量是否足够
    if (completedMessages.length < _minMessagesForSummary) {
      Logger.d(_tag,
          '消息数量不足（${completedMessages.length}/$_minMessagesForSummary），跳过自动摘要');
      return;
    }

    // 触发自动摘要
    Logger.i(_tag, '触发自动摘要...');
    _ref.read(isAutoSummarizingProvider.notifier).state = true;

    try {
      await summarizeAndUpdateTitle();
    } finally {
      _ref.read(isAutoSummarizingProvider.notifier).state = false;
    }
  }

  // 判断是否为默认标题
  bool _isDefaultTitle(String title) {
    return title.startsWith('新对话') || title == 'AI Chat' || title == '默认对话';
  }

  // 取消自动摘要定时器
  void cancelAutoSummaryTimer() {
    _autoSummaryTimer?.cancel();
    _autoSummaryTimer = null;
  }
}
