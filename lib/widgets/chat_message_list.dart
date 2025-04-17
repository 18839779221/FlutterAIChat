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

  Widget _buildMessageStatus(MessageStatus status) {
    IconData icon;
    Color color;
    String tooltip;

    switch (status) {
      case MessageStatus.generating:
        icon = Icons.sync;
        color = Colors.blue;
        tooltip = '正在生成';
        break;
      case MessageStatus.completed:
        icon = Icons.check_circle_outline;
        color = Colors.green;
        tooltip = '生成完成';
        break;
      case MessageStatus.interrupted:
        icon = Icons.pause_circle_outline;
        color = Colors.orange;
        tooltip = '生成中断';
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        tooltip = '生成失败';
        break;
      default:
        icon = Icons.circle_outlined;
        color = Colors.grey;
        tooltip = '初始状态';
    }

    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 16,
        color: color,
      ),
    );
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
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: message.isUser 
                          ? Colors.blue[100] 
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: message.isUser
                            ? Text(message.text)
                            : MarkdownBody(
                                data: message.text,
                                selectable: true,
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(fontSize: 16),
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
                        ),
                        if (!message.isUser)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _buildMessageStatus(message.status),
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
}

