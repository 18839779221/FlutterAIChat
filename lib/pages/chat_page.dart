import 'dart:async';

import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../database/database_helper.dart';
import '../utils/logger.dart';

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
  final ChatService _chatService = ChatService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;
  StreamSubscription? _streamSubscription;

  @override
  void initState() {
    super.initState();
    Logger.i(_tag, '初始化聊天页面...');
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      Logger.d(_tag, '开始加载历史消息...');
      final messages = await _dbHelper.getMessages();
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
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

    Logger.d(_tag, '准备发送新消息: ${text.substring(0, text.length.clamp(0, 50))}...');
    
    final userMessage = ChatMessage(text: text, isUser: true);
    final aiMessage = ChatMessage(text: '', isUser: false);
    
    try {
      Logger.d(_tag, '保存用户消息到数据库...');
      await _dbHelper.insertMessage(userMessage);
      
      Logger.d(_tag, '创建AI消息占位...');
      final aiMessageId = await _dbHelper.insertMessage(aiMessage);
      
      // 获取当前消息之前的历史消息
      final historyMessages = List<ChatMessage>.from(_messages);
      
      setState(() {
        _messages.add(userMessage);
        _messages.add(aiMessage);
        _isLoading = true;
      });
      
      Logger.d(_tag, '开始接收AI响应流，历史消息数量: ${historyMessages.length}');
      await _streamSubscription?.cancel();
      
      _streamSubscription = _chatService
          .sendMessageStream(text, historyMessages) // 传入历史消息
          .listen(
            (content) async {
              Logger.d(_tag, '收到AI响应片段: $content');
              setState(() {
                aiMessage.appendText(content);
              });
              await _dbHelper.updateMessage(aiMessageId, aiMessage.text);
            },
            onError: (error) {
              Logger.e(_tag, 'AI响应出错', error);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('错误: $error')),
              );
              setState(() {
                _isLoading = false;
              });
            },
            onDone: () {
              Logger.i(_tag, 'AI响应完成');
              setState(() {
                _isLoading = false;
              });
            },
          );
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息过程中出错', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      setState(() {
        _isLoading = false;
      });
    }
    
    _textController.clear();
  }

  Future<void> _clearHistory() async {
    try {
      Logger.w(_tag, '开始清除历史记录...');
      await _dbHelper.deleteAllMessages();
      setState(() {
        _messages.clear();
      });
      Logger.i(_tag, '历史记录清除成功');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('历史记录已清除')),
      );
    } catch (e) {
      Logger.e(_tag, '清除历史记录失败', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除历史记录失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearHistory,
            tooltip: '清除历史记录',
          ),
        ],
      ),
      body: Column(
        children: [
          ChatMessageList(
            messages: _messages,
            isLoading: _isLoading,
          ),
          ChatInput(
            controller: _textController,
            onSendMessage: _sendMessage,
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    Logger.i(_tag, '清理聊天页面资源...');
    _streamSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }
} 