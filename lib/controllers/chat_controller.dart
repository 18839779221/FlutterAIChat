import 'package:ai_chat/controllers/chat_debug_controller.dart';
import 'package:ai_chat/controllers/chat_preferences_controller.dart';
import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatController {
  final Ref _ref;
  final ChatSendCoordinator _sendCoordinator;
  final ChatSessionCoordinator _sessionCoordinator;
  final ChatSummaryController _summaryController;
  final ChatDebugController _debugController;
  final ChatPreferencesController _preferencesController;

  ChatController(
    this._ref, {
    required ChatSendCoordinator sendCoordinator,
    required ChatSessionCoordinator sessionCoordinator,
    required ChatSummaryController summaryController,
    required ChatDebugController debugController,
    required ChatPreferencesController preferencesController,
  })  : _sendCoordinator = sendCoordinator,
        _sessionCoordinator = sessionCoordinator,
        _summaryController = summaryController,
        _debugController = debugController,
        _preferencesController = preferencesController;

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
    await _debugController.structureMessageForDebug(message);
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
    await _preferencesController.setSystemPrompt(prompt);
  }

  void setUseReasoning(bool value) {
    _preferencesController.setUseReasoning(value);
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
