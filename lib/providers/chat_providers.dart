import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../models/chat_group.dart';
import '../database/database_helper.dart';
import '../services/chat_service.dart';
import '../utils/logger.dart';

// 数据库提供者
final databaseProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

// 聊天服务提供者
final chatServiceProvider = Provider<ChatService>((ref) {
  return ref.watch(chatServiceFactoryProvider);
});

// 聊天服务工厂提供者
final chatServiceFactoryProvider = Provider<ChatService>((ref) {
  // 创建混合策略和LLM实例的代码保持不变
  // ...
  throw UnimplementedError("需要实现创建ChatService的代码");
});

// 消息列表提供者
final messagesProvider = StateNotifierProvider<MessagesNotifier, List<ChatMessage>>((ref) {
  return MessagesNotifier(ref);
});

class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  
  MessagesNotifier(this._ref) : super([]);
  
  void setMessages(List<ChatMessage> messages) {
    state = messages;
  }
  
  void addMessage(ChatMessage message) {
    state = [message, ...state];
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
  
  void deleteMessagePair(int index) {
    final newList = [...state];
    final indexMessage = newList[index];
    ChatMessage? userMessage, aiMessage;
    
    if (indexMessage.isUser) {
      userMessage = newList[index];
      if (index > 0) {
        aiMessage = newList[index - 1];
      }
    } else {
      aiMessage = newList[index];
      if (index < newList.length - 1) {
        userMessage = newList[index + 1];
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
final groupsProvider = StateNotifierProvider<GroupsNotifier, List<ChatGroup>>((ref) {
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

// 正在生成状态提供者
final isGeneratingProvider = StateProvider<bool>((ref) => false);

// 加载更多状态提供者
final isLoadingMoreProvider = StateProvider<bool>((ref) => false);

// 是否有更多消息提供者
final hasMoreMessagesProvider = StateProvider<bool>((ref) => true);

// 自动滚动提供者
final autoScrollToBottomProvider = StateProvider<bool>((ref) => true);

// 推理模式提供者
final useReasoningProvider = StateProvider<bool>((ref) => false);

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
final streamSubscriptionProvider = StateProvider<StreamSubscription?>((ref) => null);

// 聊天控制器提供者 - 集中处理业务逻辑
final chatControllerProvider = Provider<ChatController>((ref) => ChatController(ref));

class ChatController {
  static const String _tag = 'ChatController';
  static const int _pageSize = 20;
  
  final Ref _ref;
  
  ChatController(this._ref) {
    _initScrollListener();
  }
  
  void _initScrollListener() {
    final scrollController = _ref.read(scrollControllerProvider);
    
    scrollController.addListener(() {
      // 加载更多逻辑
      if (scrollController.position.pixels <= scrollController.position.minScrollExtent + 100 && 
          !_ref.read(isLoadingMoreProvider)) {
        loadMoreMessages();
      }
      
      // 自动滚动逻辑
      if (_ref.read(isGeneratingProvider)) {
        if (scrollController.position.userScrollDirection == ScrollDirection.reverse) {
          _ref.read(autoScrollToBottomProvider.notifier).state = false;
        }
        
        if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 10) {
          _ref.read(autoScrollToBottomProvider.notifier).state = true;
        }
      }
    });
  }
  
  // 加载分组
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
  
  // 加载当前分组
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
          // 创建新分组
          await createNewGroup();
        } else {
          // 使用现有分组
          _ref.read(currentGroupProvider.notifier).state = latestGroup;
          _ref.read(systemPromptProvider.notifier).state = latestGroup.systemPrompt;
          await loadMessages();
        }
      } else {
        // 没有分组，创建新分组
        await createNewGroup();
      }
    } catch (e) {
      Logger.e(_tag, '加载当前分组失败', e);
    }
  }
  
  // 创建新分组
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
  
  // 加载消息
  Future<void> loadMessages() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return;
    
    try {
      Logger.d(_tag, '开始加载历史消息...');
      final dbHelper = _ref.read(databaseProvider);
      final messages = await dbHelper.getMessagesByGroup(currentGroup!.id!);
      final totalCount = await dbHelper.getGroupMessageCount(currentGroup.id!);

      _ref.read(messagesProvider.notifier).setMessages(messages);
      _ref.read(hasMoreMessagesProvider.notifier).state = totalCount > messages.length;
      _ref.read(isInitializingProvider.notifier).state = false;
      
      Logger.i(_tag, '成功加载 ${messages.length} 条历史消息');
    } catch (e) {
      Logger.e(_tag, '加载历史消息失败', e);
    }
  }
  
  // 加载更多消息
  Future<void> loadMoreMessages() async {
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup?.id == null) return;
    
    if (_ref.read(isLoadingMoreProvider) || 
        !_ref.read(hasMoreMessagesProvider)) return;

    _ref.read(isLoadingMoreProvider.notifier).state = true;

    try {
      final dbHelper = _ref.read(databaseProvider);
      final currentCount = _ref.read(messagesProvider).length;
      final newMessages = await dbHelper.getMessagesByGroupWithPagination(
        groupId: currentGroup!.id!,
        limit: _pageSize,
        offset: currentCount,
      );

      if (newMessages.isEmpty) {
        _ref.read(hasMoreMessagesProvider.notifier).state = false;
        return;
      }

      _ref.read(messagesProvider.notifier).insertMessages(currentCount, newMessages);
    } catch (e) {
      Logger.e(_tag, '加载更多消息失败', e);
    } finally {
      _ref.read(isLoadingMoreProvider.notifier).state = false;
    }
  }
  
  // 发送消息
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    
    final currentGroup = _ref.read(currentGroupProvider);
    if (currentGroup == null) return;

    _ref.read(focusNodeProvider).unfocus();
    Logger.d(_tag, '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...');
    
    cancelStreamSubscription();
    
    _ref.read(autoScrollToBottomProvider.notifier).state = true;

    // 如果当前分组没有ID，说明是新建的分组，需要先保存到数据库
    if (currentGroup.id == null) {
      try {
        final dbHelper = _ref.read(databaseProvider);
        // 使用第一条消息作为分组标题
        final newGroup = currentGroup.copyWith(title: text);
        final groupId = await dbHelper.insertGroup(newGroup);
        _ref.read(currentGroupProvider.notifier).state = newGroup.copyWith(id: groupId);
        // 更新分组列表
        await loadGroups();
      } catch (e) {
        Logger.e(_tag, '保存新分组失败', e);
        return;
      }
    }

    final userMessage = ChatMessage(
      text: text,
      role: MessageRole.user,
      status: MessageStatus.completed,
    );

    // 避免消息时间戳一致，延迟1毫秒
    await Future.delayed(const Duration(milliseconds: 1));

    final aiMessage = ChatMessage(
      text: '',
      role: MessageRole.assistant,
      status: MessageStatus.generating,
    );

    try {
      final dbHelper = _ref.read(databaseProvider);
      final currentGroupId = _ref.read(currentGroupProvider)!.id!;
      
      Logger.d(_tag, '保存用户消息到数据库...');
      final userMessageId = await dbHelper.insertMessage(userMessage, currentGroupId);
      userMessage.id = userMessageId;

      Logger.d(_tag, '创建AI消息占位...');
      final aiMessageId = await dbHelper.insertMessage(aiMessage, currentGroupId);
      aiMessage.id = aiMessageId;

      // 获取有效的历史消息（成对的用户消息和已完成的AI回复）
      final List<ChatMessage> historyMessages = [];
      final List<ChatMessage> messagesCopy = List<ChatMessage>.from(_ref.read(messagesProvider));
      
      // 跳过奇数长度的情况下的最后一条消息
      int i = 0;
      while (i < messagesCopy.length - 1) {
        final message1 = messagesCopy[i];
        final message2 = messagesCopy[i + 1];
        
        // 确保是一对AI回复和用户消息，且AI回复已完成
        if (message1.isAssistant && message2.isUser && message1.status == MessageStatus.completed) {
          historyMessages.add(message2); // 先添加用户消息（旧的在前）
          historyMessages.add(message1); // 再添加AI回复
        }
        
        i += 2; // 每次处理一对消息
      }

      Logger.d(_tag, '开始接收AI响应流，有效对话对数量: ${historyMessages.length / 2}');

      // 添加消息到UI
      _ref.read(messagesProvider.notifier).addMessage(userMessage);
      _ref.read(messagesProvider.notifier).addMessage(aiMessage);
      
      // 设置生成状态
      _ref.read(isGeneratingProvider.notifier).state = true;

      // 获取聊天服务
      final chatService = _ref.read(chatServiceProvider);
      
      // 获取系统提示词和推理模式设置
      final systemPrompt = _ref.read(systemPromptProvider) ?? "";
      final useReasoning = _ref.read(useReasoningProvider);
      
      // 设置流订阅
      final subscription = chatService.sendMessageStream(
        text, 
        historyMessages,
        ChatConfig(useReasoning: useReasoning, systemPrompt: systemPrompt),
      ).listen(
        (content) async {
          try {
            final data = jsonDecode(content);
            if (data['type'] == 'content') {
              Logger.d(_tag, '收到AI响应片段: ${data['content']}');
              _ref.read(messagesProvider.notifier).appendToMessage(aiMessageId, data['content']);
              await dbHelper.updateMessage(aiMessageId, aiMessage.text);
            } else if (data['type'] == 'reasoning') {
              Logger.d(_tag, '收到推理内容: ${data['content']}');
              _ref.read(messagesProvider.notifier).appendReasoningToMessage(aiMessageId, data['content']);
              await dbHelper.updateMessageReasoning(aiMessageId, aiMessage.reasoningContent);
            }
          } catch (e) {
            Logger.e(_tag, '处理响应数据失败', e);
          }
        },
        onError: (error) {
          Logger.e(_tag, 'AI响应出错', error);
          _ref.read(messagesProvider.notifier).updateMessageStatus(aiMessageId, MessageStatus.failed);
          _ref.read(isGeneratingProvider.notifier).state = false;
          dbHelper.updateMessageStatus(aiMessageId, MessageStatus.failed);
        },
        onDone: () {
          Logger.i(_tag, 'AI响应完成');
          if (aiMessage.status != MessageStatus.interrupted) {
            _ref.read(messagesProvider.notifier).updateMessageStatus(aiMessageId, MessageStatus.completed);
            _ref.read(isGeneratingProvider.notifier).state = false;
            dbHelper.updateMessageStatus(aiMessageId, MessageStatus.completed);
          }
        },
        cancelOnError: true,
      );
      
      _ref.read(streamSubscriptionProvider.notifier).state = subscription;
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息过程中出错', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      _ref.read(messagesProvider.notifier).updateMessageStatus(aiMessage.id!, MessageStatus.failed);
      _ref.read(isGeneratingProvider.notifier).state = false;
      
      final dbHelper = _ref.read(databaseProvider);
      if (aiMessage.id != null) {
        dbHelper.updateMessageStatus(aiMessage.id!, MessageStatus.failed);
      }
    }

    _ref.read(textControllerProvider).clear();
  }
  
  // 取消流订阅
  void cancelStreamSubscription() {
    final subscription = _ref.read(streamSubscriptionProvider);
    if (subscription != null) {
      subscription.cancel();
      _ref.read(streamSubscriptionProvider.notifier).state = null;
    }
    
    if (!_ref.read(isGeneratingProvider)) return;
    _ref.read(isGeneratingProvider.notifier).state = false;
    
    final messages = _ref.read(messagesProvider);
    if (messages.isEmpty) return;
    
    final lastIndex = messages.indexWhere((message) => message.role == MessageRole.assistant);
    if (lastIndex == -1) return;
    
    final aiMessage = messages[lastIndex];
    // 如果是主动取消（例如发送新消息），则标记为中断状态
    if (aiMessage.status == MessageStatus.generating) {
      _ref.read(messagesProvider.notifier).updateMessageStatus(aiMessage.id!, MessageStatus.interrupted);
      
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
  
  // 选择分组
  Future<void> selectGroup(ChatGroup group) async {
    _ref.read(currentGroupProvider.notifier).state = group;
    _ref.read(systemPromptProvider.notifier).state = group.systemPrompt;
    await loadMessages();
  }
} 