import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/chat_message.dart';
import '../models/chat_group.dart';
import '../database/database_helper.dart';
import '../services/chat_service.dart';
import '../utils/logger.dart';

class ChatStateProvider extends ChangeNotifier {
  static const String _tag = 'ChatStateProvider';
  
  // 数据
  final List<ChatMessage> _messages = [];
  List<ChatGroup> _groups = [];
  ChatGroup? _currentGroup;
  
  // 状态
  bool _isGenerating = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _autoScrollToBottom = true;
  bool _useReasoning = false;
  bool _isInitializing = true;
  String? _systemPrompt;
  
  // 服务
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late final ChatService _chatService;
  StreamSubscription? _streamSubscription;
  
  // 控制器
  final ScrollController scrollController = ScrollController();
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  
  // 常量
  static const int _pageSize = 20;
  
  // Getters
  List<ChatMessage> get messages => _messages;
  List<ChatGroup> get groups => _groups;
  ChatGroup? get currentGroup => _currentGroup;
  bool get isGenerating => _isGenerating;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get autoScrollToBottom => _autoScrollToBottom;
  bool get useReasoning => _useReasoning;
  bool get isInitializing => _isInitializing;
  String? get systemPrompt => _systemPrompt;
  
  ChatStateProvider(this._chatService) {
    _init();
  }
  
  void _init() {
    Logger.i(_tag, '初始化聊天状态管理...');
    scrollController.addListener(_onScroll);
    _loadGroups();
  }
  
  void _onScroll() {
    // 加载更多消息
    if (scrollController.position.pixels <= scrollController.position.minScrollExtent + 100 && !_isLoadingMore) {
      loadMoreMessages();
    }
    
    // 处理自动滚动逻辑
    if (_isGenerating) {
      if (scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        _autoScrollToBottom = false;
        notifyListeners();
      }
      
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 10) {
        _autoScrollToBottom = true;
        notifyListeners();
      }
    }
  }
  
  // 加载分组
  Future<void> _loadGroups() async {
    try {
      final groups = await _dbHelper.getAllGroups();
      _groups = groups;
      notifyListeners();
      await _loadCurrentGroup();
    } catch (e) {
      Logger.e(_tag, '加载分组失败', e);
    }
  }
  
  // 加载当前分组
  Future<void> _loadCurrentGroup() async {
    try {
      final latestGroup = await _dbHelper.getLatestGroup();
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
          _currentGroup = latestGroup;
          _systemPrompt = latestGroup.systemPrompt;
          notifyListeners();
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
      final newGroup = ChatGroup(
        title: '新对话 ${_groups.length + 1}',
        systemPrompt: _systemPrompt,
      );
      
      _currentGroup = newGroup;
      _messages.clear();
      _hasMoreMessages = false;
      _isInitializing = false;
      notifyListeners();
    } catch (e) {
      Logger.e(_tag, '创建新分组失败', e);
    }
  }
  
  // 加载消息
  Future<void> loadMessages() async {
    if (_currentGroup == null) return;
    
    try {
      Logger.d(_tag, '开始加载历史消息...');
      final messages = await _dbHelper.getMessagesByGroup(_currentGroup!.id!);
      final totalCount = await _dbHelper.getGroupMessageCount(_currentGroup!.id!);

      _messages.clear();
      _messages.addAll(messages);
      _hasMoreMessages = totalCount > messages.length;
      _isInitializing = false;
      notifyListeners();
      
      Logger.i(_tag, '成功加载 ${messages.length} 条历史消息');
    } catch (e) {
      Logger.e(_tag, '加载历史消息失败', e);
    }
  }
  
  // 加载更多消息
  Future<void> loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _currentGroup == null) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final currentCount = _messages.length;
      final newMessages = await _dbHelper.getMessagesByGroupWithPagination(
        groupId: _currentGroup!.id!,
        limit: _pageSize,
        offset: currentCount,
      );

      if (newMessages.isEmpty) {
        _hasMoreMessages = false;
        notifyListeners();
        return;
      }

      _messages.addAll(newMessages);
      notifyListeners();
    } catch (e) {
      Logger.e(_tag, '加载更多消息失败', e);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }
  
  // 发送消息
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _currentGroup == null) return;

    focusNode.unfocus();
    Logger.d(_tag, '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...');
    
    cancelStreamSubscription();
    
    _autoScrollToBottom = true;
    notifyListeners();

    // 如果当前分组没有ID，说明是新建的分组，需要先保存到数据库
    if (_currentGroup!.id == null) {
      try {
        // 使用第一条消息作为分组标题
        final newGroup = _currentGroup!.copyWith(title: text);
        final groupId = await _dbHelper.insertGroup(newGroup);
        _currentGroup = newGroup.copyWith(id: groupId);
        // 更新分组列表
        await _loadGroups();
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
      Logger.d(_tag, '保存用户消息到数据库...');
      final userMessageId = await _dbHelper.insertMessage(userMessage, _currentGroup!.id!);
      userMessage.id = userMessageId;

      Logger.d(_tag, '创建AI消息占位...');
      final aiMessageId = await _dbHelper.insertMessage(aiMessage, _currentGroup!.id!);
      aiMessage.id = aiMessageId;

      // 获取有效的历史消息（成对的用户消息和已完成的AI回复）
      final List<ChatMessage> historyMessages = [];
      final List<ChatMessage> messagesCopy = List<ChatMessage>.from(_messages);
      
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

      _messages.insert(0, userMessage);
      _messages.insert(0, aiMessage);
      _isGenerating = true;
      notifyListeners();

      _streamSubscription = _chatService.sendMessageStream(
        text, 
        historyMessages,
        ChatConfig(useReasoning: _useReasoning, systemPrompt: _systemPrompt ?? ""),
      ).listen(
        (content) async {
          try {
            final data = jsonDecode(content);
            if (data['type'] == 'content') {
              Logger.d(_tag, '收到AI响应片段: ${data['content']}');
              aiMessage.appendText(data['content']);
              await _dbHelper.updateMessage(aiMessageId, aiMessage.text);
              notifyListeners();
            } else if (data['type'] == 'reasoning') {
              Logger.d(_tag, '收到推理内容: ${data['content']}');
              aiMessage.appendReasoning(data['content']);
              await _dbHelper.updateMessageReasoning(aiMessageId, aiMessage.reasoningContent);
              notifyListeners();
            }
          } catch (e) {
            Logger.e(_tag, '处理响应数据失败', e);
          }
        },
        onError: (error) {
          Logger.e(_tag, 'AI响应出错', error);
          aiMessage.status = MessageStatus.failed;
          _isGenerating = false;
          _dbHelper.updateMessageStatus(aiMessageId, MessageStatus.failed);
          notifyListeners();
        },
        onDone: () {
          Logger.i(_tag, 'AI响应完成');
          if (aiMessage.status != MessageStatus.interrupted) {
            aiMessage.status = MessageStatus.completed;
            _isGenerating = false;
            _dbHelper.updateMessageStatus(aiMessageId, MessageStatus.completed);
            notifyListeners();
          }
        },
        cancelOnError: true,
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息过程中出错', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      aiMessage.status = MessageStatus.failed;
      _isGenerating = false;
      if (aiMessage.id != null) {
        _dbHelper.updateMessageStatus(aiMessage.id!, MessageStatus.failed);
      }
      notifyListeners();
    }

    textController.clear();
  }
  
  // 取消流订阅
  void cancelStreamSubscription() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    
    if (!_isGenerating) return;
    _isGenerating = false;
    
    if (_messages.isEmpty) {
      notifyListeners();
      return;
    }
    
    final lastIndex = _messages.lastIndexWhere((message) => message.role == MessageRole.assistant);
    if (lastIndex == -1) {
      notifyListeners();
      return;
    }
    
    final aiMessage = _messages[lastIndex];
    // 如果是主动取消（例如发送新消息），则标记为中断状态
    if (aiMessage.status == MessageStatus.generating) {
      aiMessage.status = MessageStatus.interrupted;
      if (aiMessage.id != null) {
        _dbHelper.updateMessageStatus(aiMessage.id!, MessageStatus.interrupted);
      }
    }
    
    notifyListeners();
  }
  
  // 删除消息对
  Future<void> deleteMessagePair(int index) async {
    try {
      final indexMessage = _messages[index];
      ChatMessage? userMessage, aiMessage;
      if (indexMessage.isUser) {
        userMessage = _messages[index];
        if (index > 0) {
          aiMessage = _messages[index - 1];
        }
      } else {
        aiMessage = _messages[index];
        if (index < _messages.length - 1) {
          userMessage = _messages[index + 1];
        }
      }

      // 找到对应的AI消息
      if (!(userMessage != null && aiMessage != null && userMessage.isUser && userMessage.id != null && aiMessage.isAssistant && aiMessage.id != null)) {
        return;
      }

      // 从数据库中删除消息对
      await Future(() {
        _dbHelper.deleteMessage(userMessage!.id!);
        _dbHelper.deleteMessage(aiMessage!.id!);
      });

      // 从内存中删除消息
      _messages.remove(aiMessage);
      _messages.remove(userMessage);
      notifyListeners();
    } catch (e) {
      Logger.e(_tag, '删除消息失败', e);
    }
  }
  
  // 删除分组
  Future<void> deleteGroup(ChatGroup group) async {
    try {
      Logger.w(_tag, '开始删除分组: ${group.title}');
      
      // 删除分组及其所有消息
      await _dbHelper.deleteGroup(group.id!);
      
      // 如果删除的是当前分组，需要切换到其他分组
      if (_currentGroup?.id == group.id) {
        final latestGroup = await _dbHelper.getLatestGroup();
        if (latestGroup != null) {
          _currentGroup = latestGroup;
          _systemPrompt = latestGroup.systemPrompt;
          notifyListeners();
          await loadMessages();
        } else {
          // 如果没有其他分组，创建新分组
          await createNewGroup();
        }
      }
      
      // 重新加载分组列表
      await _loadGroups();
      
      Logger.i(_tag, '分组删除成功');
    } catch (e) {
      Logger.e(_tag, '删除分组失败', e);
    }
  }
  
  // 设置系统提示词
  Future<void> setSystemPrompt(String? prompt) async {
    _systemPrompt = prompt;
    if (_currentGroup != null && _currentGroup!.id != null) {
      await _dbHelper.updateGroupSystemPrompt(_currentGroup!.id!, prompt);
    }
    notifyListeners();
  }
  
  // 设置推理模式
  void setUseReasoning(bool value) {
    _useReasoning = value;
    notifyListeners();
  }
  
  // 选择分组
  Future<void> selectGroup(ChatGroup group) async {
    _currentGroup = group;
    _systemPrompt = group.systemPrompt;
    notifyListeners();
    await loadMessages();
  }
  
  @override
  void dispose() {
    Logger.i(_tag, '清理聊天状态资源...');
    _streamSubscription?.cancel();
    textController.dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
} 