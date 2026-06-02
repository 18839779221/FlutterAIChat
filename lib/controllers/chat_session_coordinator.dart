import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/providers/chat_collection_providers.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_ui_providers.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ChatSessionCoordinator {
  Future<void> loadGroups();

  Future<void> loadCurrentGroup();

  Future<void> createNewGroup();

  Future<void> deleteGroup(int id);

  Future<void> loadMessages();

  Future<void> loadMoreMessages();

  Future<void> selectGroup(ChatGroup group);

  Future<void> updateCurrentGroupWorkspace(String? workspaceId);
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
      final lockedProviderStyle = await _resolveCurrentProviderStyle();
      final newGroup = ChatGroup(
        title: '新对话 ${groups.length + 1}',
        systemPrompt: systemPrompt,
        lockedProviderStyle: lockedProviderStyle,
      );

      _ref.read(currentGroupProvider.notifier).state = newGroup;
      _ref.read(messagesProvider.notifier).clearMessages();
      _ref.read(hasMoreMessagesProvider.notifier).state = false;
      _ref.read(isInitializingProvider.notifier).state = false;
    } catch (e) {
      Logger.e(_tag, '创建新分组失败', e);
    }
  }

  Future<ChatTurnProviderStyle> _resolveCurrentProviderStyle() async {
    try {
      final config =
          await _ref.read(appSettingsRepositoryProvider).getLlmConfig();
      final apiStyle = const ApiProtocolResolver().resolveStyle(config.apiUrl);
      return apiStyle.toChatTurnProviderStyle();
    } catch (e) {
      Logger.w(
        _tag,
        '无法读取当前 provider style，新会话回落到 Chat Completions: $e',
      );
      return ChatTurnProviderStyle.openaiChatCompletions;
    }
  }

  @override
  Future<void> deleteGroup(int id) async {
    try {
      final dbHelper = _ref.read(databaseProvider);
      await dbHelper.deleteGroup(id);
      _ref.read(groupsProvider.notifier).setGroups(
            _ref.read(groupsProvider).where((group) => group.id != id).toList(),
          );

      final currentGroup = _ref.read(currentGroupProvider);
      if (currentGroup?.id != id) {
        return;
      }

      final latestGroup = await dbHelper.getLatestGroup();
      if (latestGroup != null) {
        _ref.read(currentGroupProvider.notifier).state = latestGroup;
        _ref.read(systemPromptProvider.notifier).state =
            latestGroup.systemPrompt;
        await loadMessages();
        return;
      }

      await createNewGroup();
    } catch (e) {
      Logger.e(_tag, '删除分组失败', e);
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

  @override
  Future<void> updateCurrentGroupWorkspace(String? workspaceId) async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup == null) {
      return;
    }

    final normalizedWorkspaceId = workspaceId?.trim().isEmpty ?? true
        ? null
        : workspaceId!.trim();
    if (currentGroup.workspaceId == normalizedWorkspaceId) {
      return;
    }

    final updatedGroup = currentGroup.copyWith(workspaceId: normalizedWorkspaceId);
    _ref.read(currentGroupProvider.notifier).state = updatedGroup;

    final groups = _ref.read(groupsProvider);
    final nextGroups = groups
        .map(
          (group) => group.id == currentGroup.id ? updatedGroup : group,
        )
        .toList(growable: false);
    _ref.read(groupsProvider.notifier).setGroups(nextGroups);

    if (currentGroup.id != null) {
      await _ref
          .read(databaseProvider)
          .updateGroupWorkspaceId(currentGroup.id!, normalizedWorkspaceId);
    }
  }
}
