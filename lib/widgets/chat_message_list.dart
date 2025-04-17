import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import 'code_block_builder.dart';

class ChatMessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isLoading;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.isLoading,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 获取状态指示器颜色
  Color _getStatusColor(MessageStatus status) {
    switch (status) {
      case MessageStatus.generating:
        return Colors.blue.withOpacity(0.5);
      case MessageStatus.completed:
        return Colors.green.withOpacity(0.3);
      case MessageStatus.interrupted:
        return Colors.orange.withOpacity(0.3);
      case MessageStatus.failed:
        return Colors.red.withOpacity(0.3);
      default:
        return Colors.grey.withOpacity(0.3);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scrollToBottom();
    
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final message = widget.messages[index];
                return Align(
                  alignment: message.isUser 
                      ? Alignment.centerRight 
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Stack(
                      children: [
                        // 状态背景指示器
                        if (!message.isUser && message.status != MessageStatus.completed)
                          Positioned.fill(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                color: _getStatusColor(message.status),
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                          ),
                        // 消息内容
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: message.isUser 
                                ? Colors.blue[100] 
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12.0),
                            border: !message.isUser && message.status != MessageStatus.completed
                                ? Border.all(
                                    color: _getStatusColor(message.status),
                                    width: 1.0,
                                  )
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 消息内容
                              message.isUser
                                  ? Text(message.text)
                                  : MarkdownBody(
                                      data: message.text,
                                      selectable: true,
                                      styleSheet: MarkdownStyleSheet(
                                        p: const TextStyle(fontSize: 16),
                                        code: TextStyle(
                                          backgroundColor: Colors.grey[200],
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                        ),
                                        codeblockDecoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      builders: {
                                        'code': CodeElementBuilder(),
                                        'pre': CodeBlockBuilder(),
                                      },
                                    ),
                              // 状态提示文本（仅在非完成状态下显示）
                              if (!message.isUser && message.status != MessageStatus.completed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _getStatusText(message.status),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _getStatusColor(message.status).withOpacity(0.8),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  String _getStatusText(MessageStatus status) {
    switch (status) {
      case MessageStatus.generating:
        return '正在生成...';
      case MessageStatus.interrupted:
        return '生成已中断';
      case MessageStatus.failed:
        return '生成失败';
      default:
        return '';
    }
  }
}

