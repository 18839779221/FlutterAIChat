import 'dart:async';

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    Logger.i(_tag, '初始化聊天页面...');

    // 页面初始化时调起软键盘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _initChatService();
    _loadMessages();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 100 && !_isLoadingMore) {
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

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final currentCount = _messages.length;
      final newMessages = await _dbHelper.getMessagesWithPagination(
        limit: _pageSize,
        offset: currentCount,
      );

      if (newMessages.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
        });
        return;
      }

      // 将新消息插入到列表开头
      setState(() {
        _messages.insertAll(0, newMessages);
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

  Future<void> _loadMessages() async {
    try {
      Logger.d(_tag, '开始加载历史消息...');
      final messages = await _dbHelper.getMessages();
      final totalCount = await _dbHelper.getTotalMessageCount();

      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _hasMoreMessages = totalCount > messages.length;
        _isInitializing = false;
      });
      Logger.i(_tag, '成功加载 ${messages.length} 条历史消息');
    } catch (e) {
      Logger.e(_tag, '加载历史消息失败', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载历史消息失败: $e')),
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _focusNode.unfocus();

    Logger.d(
        _tag, '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...');

    // 取消当前正在进行的响应
    cancelStreamSubscription();

    final userMessage = ChatMessage(
      text: text,
      role: MessageRole.user,
      status: MessageStatus.completed, // 用户消息直接标记为完成
    );

    final aiMessage = ChatMessage(
      text: '',
      role: MessageRole.assistant,
      status: MessageStatus.generating, // AI 消息初始状态为生成中
    );

    try {
      Logger.d(_tag, '保存用户消息到数据库...');
      await _dbHelper.insertMessage(userMessage);

      Logger.d(_tag, '创建AI消息占位...');
      final aiMessageId = await _dbHelper.insertMessage(aiMessage);
      aiMessage.id = aiMessageId;

      // 获取当前消息之前的历史消息
      final historyMessages = List<ChatMessage>.from(_messages);

      setState(() {
        _messages.add(userMessage);
        _messages.add(aiMessage);
        _isGenerating = true;
      });

      Logger.d(_tag, '开始接收AI响应流，历史消息数量: ${historyMessages.length}');

      _streamSubscription =
          _chatService.sendMessageStream(text, historyMessages).listen(
        (content) async {
          if (!mounted) return;
          Logger.d(_tag, '收到AI响应片段: $content');
          setState(() {
            aiMessage.appendText(content);
          });
          await _dbHelper.updateMessage(aiMessageId, aiMessage.text);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const ChatDrawer(),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空历史记录',
            onPressed: _showClearHistoryDialog,
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            _scaffoldKey.currentState?.openDrawer();
          }
        },
        child: Stack(
          children: [
            Column(children: [
              Expanded(
                child: ChatMessageList(
                  messages: _messages,
                  isGenerating: _isGenerating,
                  inputFocusNode: _focusNode,
                  scrollController: _scrollController,
                  isLoadingMore: _isLoadingMore,
                  hasMoreMessages: _hasMoreMessages,
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
                ),
              ),
            ]),
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
