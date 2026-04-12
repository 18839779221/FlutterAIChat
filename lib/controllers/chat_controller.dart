import 'dart:convert';

import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatController {
  final Ref _ref;
  final ChatSendCoordinator _sendCoordinator;
  final ChatSessionCoordinator _sessionCoordinator;
  final ChatSummaryController _summaryController;

  ChatController(
    this._ref, {
    required ChatSendCoordinator sendCoordinator,
    required ChatSessionCoordinator sessionCoordinator,
    required ChatSummaryController summaryController,
  })  : _sendCoordinator = sendCoordinator,
        _sessionCoordinator = sessionCoordinator,
        _summaryController = summaryController {
    _initScrollListener();
  }

  void _initScrollListener() {
    final scrollController = _ref.read(scrollControllerProvider);

    scrollController.addListener(() {
      if (scrollController.position.pixels <=
              scrollController.position.minScrollExtent + 100 &&
          !_ref.read(isLoadingMoreProvider)) {
        loadMoreMessages();
      }

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

  Future<void> loadGroups() async {
    await _sessionCoordinator.loadGroups();
  }

  Future<void> loadCurrentGroup() async {
    await _sessionCoordinator.loadCurrentGroup();
  }

  Future<void> createNewGroup() async {
    await _sessionCoordinator.createNewGroup();
  }

  Future<void> deleteGroup(int id) async {
    await _sessionCoordinator.deleteGroup(id);
  }

  Future<void> loadMessages() async {
    await _sessionCoordinator.loadMessages();
  }

  Future<void> loadMoreMessages() async {
    await _sessionCoordinator.loadMoreMessages();
  }

  Future<void> sendMessage(String text) async {
    await _sendCoordinator.sendMessage(
          text,
          scheduleAutoSummary: _summaryController.scheduleAutoSummary,
          cancelActiveStream: cancelStreamSubscription,
        );
  }

  Future<void> cancelToolInvocation(ChatMessage message) async {
    await _sendCoordinator.cancelToolInvocation(message);
  }

  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {
    await _sendCoordinator.confirmToolInvocation(
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

  Future<void> setSystemPrompt(String? prompt) async {
    _ref.read(systemPromptProvider.notifier).state = prompt;

    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup != null && currentGroup.id != null) {
      final dbHelper = _ref.read(databaseProvider);
      await dbHelper.updateGroupSystemPrompt(currentGroup.id!, prompt);
    }
  }

  void setUseReasoning(bool value) {
    _ref.read(useReasoningProvider.notifier).state = value;
  }

  void setUseConciseMode(bool value) {
    final currentPrompt = _ref.read(systemPromptProvider);
    final cachedPrompt = _ref.read(cachedSystemPromptProvider);

    if (value) {
      if (cachedPrompt == null) {
        _ref.read(cachedSystemPromptProvider.notifier).state = currentPrompt;
      }
      setSystemPrompt("极简模式，只回答问题本身，无需任何解释背景和扩展，尽量控制在30字之内(特殊情况下允许超出)");
    } else {
      setSystemPrompt(cachedPrompt);
      _ref.read(cachedSystemPromptProvider.notifier).state = null;
    }

    _ref.read(useConciseModeProvider.notifier).state = value;
  }

  Future<void> selectGroup(ChatGroup group) async {
    await _sessionCoordinator.selectGroup(group);
  }

  Future<String?> summarizeAndUpdateTitle() async {
    return _summaryController.summarizeAndUpdateTitle();
  }

  void cancelAutoSummaryTimer() {
    _summaryController.cancelAutoSummaryTimer();
  }
}
