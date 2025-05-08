import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat_group.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../database/database_helper.dart';
import '../utils/logger.dart';
import '../models/llm/llm_factory.dart';
import '../models/context/context_strategies.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/chat_drawer.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.title});

  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String _tag = 'ChatPage';
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final ChatService _chatService;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isGenerating = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  StreamSubscription? _streamSubscription;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitializing = true;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;
  bool _useReasoning = false;
  String? _systemPrompt;
  List<ChatGroup> _groups = [];
  ChatGroup? _currentGroup;

  @override
  void initState() {
    super.initState();
    Logger.i(_tag, '初始化聊天页面...');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _initChatService();
    _loadGroups();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= _scrollController.position.minScrollExtent + 100 && !_isLoadingMore) {
      _loadMoreMessages();
    }
  }

  void _initChatService() {
    // 创建混合策略
    final contextStrategy = HybridStrategy(
      strategies: [
        TokenBasedStrategy(),
        SmartSelectionStrategy(),
      ],
      weights: [0.7, 0.3], // 70% token基础，30% 智能选择
    );

    // 创建DeepSeek模型实例
    final llm = LLMFactory.createLLM(LLMType.deepseek);

    // 创建聊天服务
    _chatService = ChatService(
      llm: llm,
      contextStrategy: contextStrategy,
      maxTokens: 4000,
    );
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await _dbHelper.getAllGroups();
      setState(() {
        _groups = groups;
      });
      await _loadCurrentGroup();
    } catch (e) {
      Logger.e(_tag, '加载分组失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载分组失败: $e')),
        );
      }
    }
  }

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
          await _createNewGroup();
        } else {
          // 使用现有分组
          setState(() {
            _currentGroup = latestGroup;
            _systemPrompt = latestGroup.systemPrompt;
          });
          await _loadMessages();
        }
      } else {
        // 没有分组，创建新分组
        await _createNewGroup();
      }
    } catch (e) {
      Logger.e(_tag, '加载当前分组失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载当前分组失败: $e')),
        );
      }
    }
  }

  Future<void> _createNewGroup() async {
    try {
      final newGroup = ChatGroup(
        title: '新对话 ${_groups.length + 1}',
        systemPrompt: _systemPrompt,
      );
      
      setState(() {
        _currentGroup = newGroup;
        _messages.clear();
        _hasMoreMessages = false;
      });
    } catch (e) {
      Logger.e(_tag, '创建新分组失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建新分组失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_currentGroup == null) return;
    
    try {
      Logger.d(_tag, '开始加载历史消息...');
      final messages = await _dbHelper.getMessagesByGroup(_currentGroup!.id!);
      final totalCount = await _dbHelper.getGroupMessageCount(_currentGroup!.id!);

      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _hasMoreMessages = totalCount > messages.length;
        _isInitializing = false;
      });
      Logger.i(_tag, '成功加载 ${messages.length} 条历史消息');
    } catch (e) {
      Logger.e(_tag, '加载历史消息失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载历史消息失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _currentGroup == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final currentCount = _messages.length;
      final newMessages = await _dbHelper.getMessagesByGroupWithPagination(
        groupId: _currentGroup!.id!,
        limit: _pageSize,
        offset: currentCount,
      );

      if (newMessages.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
        });
        return;
      }

      setState(() {
        _messages.addAll(newMessages);
      });
    } catch (e) {
      Logger.e(_tag, '加载更多消息失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多消息失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _currentGroup == null) return;

    _focusNode.unfocus();

    Logger.d(_tag, '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...');

    cancelStreamSubscription();

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存新分组失败: $e')),
          );
        }
        return;
      }
    }

    final userMessage = ChatMessage(
      text: text,
      role: MessageRole.user,
      status: MessageStatus.completed,
    );

    // 避免消息时间戳一致，延迟1毫秒
    sleep(Duration(milliseconds: 1));

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

      // 获取当前消息之前的历史消息
      final historyMessages = List<ChatMessage>.from(_messages);

      setState(() {
        _messages.insert(0, userMessage);
        _messages.insert(0, aiMessage);
        _isGenerating = true;
      });

      Logger.d(_tag, '开始接收AI响应流，历史消息数量: ${historyMessages.length}');

      _streamSubscription = _chatService.sendMessageStream(
        text, 
        historyMessages,
        ChatConfig(useReasoning: _useReasoning),
      ).listen(
        (content) async {
          if (!mounted) return;
          
          try {
            final data = jsonDecode(content);
            if (data['type'] == 'content') {
              Logger.d(_tag, '收到AI响应片段: ${data['content']}');
              setState(() {
                aiMessage.appendText(data['content']);
              });
              await _dbHelper.updateMessage(aiMessageId, aiMessage.text);
            } else if (data['type'] == 'reasoning') {
              Logger.d(_tag, '收到推理内容: ${data['content']}');
              setState(() {
                aiMessage.appendReasoning(data['content']);
              });
              await _dbHelper.updateMessageReasoning(aiMessageId, aiMessage.reasoningContent);
            }
          } catch (e) {
            Logger.e(_tag, '处理响应数据失败', e);
          }
        },
        onError: (error) {
          Logger.e(_tag, 'AI响应出错', error);
          if (!mounted) return;
          setState(() {
            aiMessage.status = MessageStatus.failed;
            _isGenerating = false;
          });
          _dbHelper.updateMessageStatus(aiMessageId, MessageStatus.failed);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('错误: $error')),
          );
        },
        onDone: () {
          Logger.i(_tag, 'AI响应完成');
          if (!mounted) return;
          if (aiMessage.status != MessageStatus.interrupted) {
            setState(() {
              aiMessage.status = MessageStatus.completed;
              _isGenerating = false;
            });
            _dbHelper.updateMessageStatus(aiMessageId, MessageStatus.completed);
          }
        },
        cancelOnError: true,
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息过程中出错', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      if (!mounted) return;
      setState(() {
        aiMessage.status = MessageStatus.failed;
        _isGenerating = false;
      });
      if (aiMessage.id != null) {
        _dbHelper.updateMessageStatus(aiMessage.id!, MessageStatus.failed);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    _textController.clear();
  }

  void _showSystemPromptDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('系统提示词'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: CupertinoTextField(
            controller: TextEditingController(text: _systemPrompt),
            placeholder: '输入系统提示词...',
            maxLines: 5,
            minLines: 3,
            onChanged: (value) {
              _systemPrompt = value;
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () async {
              if (_currentGroup != null) {
                await _dbHelper.updateGroupSystemPrompt(_currentGroup!.id!, _systemPrompt);
              }
              setState(() {});
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void cancelStreamSubscription() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isGenerating = false;
    if (_messages.isEmpty) return;
    final lastIndex = _messages
        .lastIndexWhere((message) => message.role == MessageRole.assistant);
    if (lastIndex == -1) return;
    final aiMessage = _messages[lastIndex];
    // 如果是主动取消（例如发送新消息），则标记为中断状态
    if (aiMessage.status == MessageStatus.generating) {
      setState(() {
        aiMessage.status = MessageStatus.interrupted;
      });
      if (aiMessage.id != null) {
        Future(() => _dbHelper.updateMessageStatus(
            aiMessage.id!, MessageStatus.interrupted));
      }
    }
  }

  Future<void> _showClearHistoryDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ConfirmDialog(
          title: '确认清空',
          content: '确定要清空所有聊天记录吗？此操作不可恢复。',
          confirmText: '清空',
          onConfirm: _clearHistory,
        );
      },
    );
  }

  Future<void> _clearHistory() async {
    try {
      Logger.w(_tag, '开始清除历史记录...');
      await _dbHelper.deleteAllMessages();
      setState(() {
        _messages.clear();
      });
      Logger.i(_tag, '历史记录清除成功');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('历史记录已清除'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Logger.e(_tag, '清除历史记录失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清除历史记录失败: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _deleteMessagePair(int index) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('待删除消息未找到')),
        );
        return;
      }

      // 从数据库中删除消息对
      await Future(() {
        _dbHelper.deleteMessage(userMessage!.id!);
        _dbHelper.deleteMessage(aiMessage!.id!);
      });

      // 从内存中删除消息
      setState(() {
        _messages.remove(aiMessage);
        _messages.remove(userMessage);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('消息已删除')),
        );
      }
    } catch (e) {
      Logger.e(_tag, '删除消息失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除消息失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteGroup(ChatGroup group) async {
    try {
      Logger.w(_tag, '开始删除分组: ${group.title}');
      
      // 删除分组及其所有消息
      await _dbHelper.deleteGroup(group.id!);
      
      // 如果删除的是当前分组，需要切换到其他分组
      if (_currentGroup?.id == group.id) {
        final latestGroup = await _dbHelper.getLatestGroup();
        if (latestGroup != null) {
          setState(() {
            _currentGroup = latestGroup;
            _systemPrompt = latestGroup.systemPrompt;
          });
          await _loadMessages();
        } else {
          // 如果没有其他分组，创建新分组
          await _createNewGroup();
        }
      }
      
      // 重新加载分组列表
      await _loadGroups();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('分组已删除'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      Logger.i(_tag, '分组删除成功');
    } catch (e) {
      Logger.e(_tag, '删除分组失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除分组失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: ChatDrawer(
        groups: _groups,
        currentGroup: _currentGroup,
        onGroupSelected: (group) async {
          setState(() {
            _currentGroup = group;
            _systemPrompt = group.systemPrompt;
          });
          await _loadMessages();
          if (mounted) {
            Navigator.pop(context);
          }
        },
        onNewGroup: () async {
          await _createNewGroup();
          if (mounted) {
            Navigator.pop(context);
          }
        },
        onDeleteGroup: _deleteGroup,
        isGenerating: _isGenerating,
      ),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: GestureDetector(
          onTap: () {
            showCupertinoModalPopup(
              context: context,
              builder: (context) => CupertinoActionSheet(
                title: const Text('AI Chat'),
                message: const Text('选择操作'),
                actions: [
                  CupertinoActionSheetAction(
                    child: Text(_systemPrompt != null && _systemPrompt!.isNotEmpty 
                      ? '修改系统提示词' 
                      : '设置系统提示词'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSystemPromptDialog();
                    },
                  ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建对话',
            onPressed: !_isGenerating ? _createNewGroup : null,
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            _scaffoldKey.currentState?.openDrawer();
          }
        },
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  ChatMessageList(
                    messages: _messages,
                    isGenerating: _isGenerating,
                    inputFocusNode: _focusNode,
                    scrollController: _scrollController,
                    isLoadingMore: _isLoadingMore,
                    hasMoreMessages: _hasMoreMessages,
                    onDeleteMessage: _deleteMessagePair,
                  ),
                  if (_isLoadingMore)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: ChatInput(
                controller: _textController,
                focusNode: _focusNode,
                onSendMessage: _sendMessage,
                isGenerating: _isGenerating,
                onCancel: cancelStreamSubscription,
                useReasoning: _useReasoning,
                onReasoningChanged: (value) {
                  setState(() {
                    _useReasoning = value;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    Logger.i(_tag, '清理聊天页面资源...');
    _streamSubscription?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
