import 'dart:async';

import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ChatSummaryController {
  Future<String?> summarizeAndUpdateTitle();

  void scheduleAutoSummary();

  void cancelAutoSummaryTimer();
}

class DefaultChatSummaryController implements ChatSummaryController {
  static const String _tag = 'ChatSummaryController';
  static const int _minMessagesForSummary = 6;
  static const int _inactivitySeconds = 30;

  final Ref _ref;
  final ChatSessionCoordinator _sessionCoordinator;
  Timer? _autoSummaryTimer;

  DefaultChatSummaryController(
    this._ref, {
    required ChatSessionCoordinator sessionCoordinator,
  }) : _sessionCoordinator = sessionCoordinator;

  @override
  Future<String?> summarizeAndUpdateTitle() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return null;

    final messages = _ref.read(messagesProvider);
    if (messages.isEmpty) return null;

    try {
      Logger.i(_tag, '开始生成对话摘要...');

      final completedMessages = messages
          .where((msg) => msg.status == MessageStatus.completed)
          .toList()
          .reversed
          .toList();

      if (completedMessages.isEmpty) return null;

      final chatService = _ref.read(chatServiceProvider);
      final summary =
          await chatService.llm.summarizeConversation(completedMessages);

      final dbHelper = _ref.read(databaseProvider);
      await dbHelper.updateGroupTitle(currentGroup!.id!, summary,
          isSummarized: true);

      _ref.read(currentGroupProvider.notifier).state =
          currentGroup.copyWith(title: summary, isSummarized: true);

      await _sessionCoordinator.loadGroups();

      Logger.i(_tag, '对话摘要生成成功: $summary');
      return summary;
    } catch (e) {
      Logger.e(_tag, '生成对话摘要失败', e);
      return null;
    }
  }

  @override
  void scheduleAutoSummary() {
    _autoSummaryTimer?.cancel();
    _autoSummaryTimer = Timer(const Duration(seconds: _inactivitySeconds), () {
      _checkAndTriggerAutoSummary();
    });
  }

  Future<void> _checkAndTriggerAutoSummary() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return;

    if (currentGroup!.isSummarized) {
      Logger.d(_tag, '分组已经生成过摘要，跳过自动摘要');
      return;
    }

    if (_ref.read(isGeneratingProvider) ||
        _ref.read(isAutoSummarizingProvider)) {
      Logger.d(_tag, '正在生成消息或摘要中，跳过自动摘要');
      return;
    }

    if (!_isDefaultTitle(currentGroup.title)) {
      Logger.d(_tag, '标题已自定义，跳过自动摘要');
      return;
    }

    final messages = _ref.read(messagesProvider);
    final completedMessages =
        messages.where((msg) => msg.status == MessageStatus.completed).toList();

    if (completedMessages.length < _minMessagesForSummary) {
      Logger.d(_tag,
          '消息数量不足（${completedMessages.length}/$_minMessagesForSummary），跳过自动摘要');
      return;
    }

    Logger.i(_tag, '触发自动摘要...');
    _ref.read(isAutoSummarizingProvider.notifier).state = true;

    try {
      await summarizeAndUpdateTitle();
    } finally {
      _ref.read(isAutoSummarizingProvider.notifier).state = false;
    }
  }

  bool _isDefaultTitle(String title) {
    return title.startsWith('新对话') || title == 'AI Chat' || title == '默认对话';
  }

  @override
  void cancelAutoSummaryTimer() {
    _autoSummaryTimer?.cancel();
    _autoSummaryTimer = null;
  }
}
