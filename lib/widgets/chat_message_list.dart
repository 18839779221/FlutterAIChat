import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/markdown/markdown_widget_impl.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../providers/chat_state_provider.dart';

class ChatMessageList extends StatefulWidget {
  const ChatMessageList({super.key});

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  // 是否快滑到了底部
  bool _isNearBottom = true;

  @override
  Widget build(BuildContext context) {
    final chatState = Provider.of<ChatStateProvider>(context);
    
    if (chatState.isGenerating && chatState.autoScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (chatState.scrollController.hasClients) {
          chatState.scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Colors.white,
                Colors.white,
                _isNearBottom ? Colors.white : Colors.white.withOpacity(0.0),
              ],
              stops: const [0.0, 0.7, 0.9, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: chatState.scrollController,
            padding: const EdgeInsets.all(8.0),
            reverse: true,
            itemCount: chatState.messages.length + (chatState.hasMoreMessages ? 1 : 0),
            itemBuilder: (context, index) {
              if (chatState.hasMoreMessages && index >= chatState.messages.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final message = chatState.messages[index];
              return Align(
                alignment: message.isUser 
                    ? Alignment.centerRight 
                    : Alignment.centerLeft,
                child: _buildMessageItem(message, context),
              );
            },
          ),
        ),
        if (!_isNearBottom)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.9),
              onPressed: _scrollToBottom,
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    chatState.scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    chatState.scrollController.removeListener(_scrollListener);
    super.dispose();
  }

  void _scrollListener() {
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    final currentScroll = chatState.scrollController.offset;
    final isNearBottom = currentScroll <= 100;

    if (_isNearBottom != isNearBottom) {
      setState(() {
        _isNearBottom = isNearBottom;
      });
    }

    final scrollingPosition = chatState.scrollController.position;
    // 用户向下滑动，且不是惯性滑动时收起输入框
    if (scrollingPosition.userScrollDirection == ScrollDirection.reverse &&
        scrollingPosition.activity is DragScrollActivity) {
      chatState.focusNode.unfocus();
    }
  }

  void _scrollToBottom() {
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    chatState.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // 获取状态指示器颜色
  Color _getStatusColor(MessageStatus status) {
    switch (status) {
      case MessageStatus.generating:
        return Colors.blue.withOpacity(0.1);
      case MessageStatus.completed:
        return Colors.green.withOpacity(0.2);
      case MessageStatus.interrupted:
        return Colors.orange.withOpacity(0.2);
      case MessageStatus.failed:
        return Colors.red.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  Widget _buildMessageItem(ChatMessage message, BuildContext context) {
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: GestureDetector(
        onLongPress: () {
          _showMessageOptionMenu(message, context);
        },
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
                color: message.isUser ? Colors.blue[50] : Colors.grey[180],
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
                  // 推理内容
                  if (!message.isUser && message.reasoningContent != null && message.reasoningContent!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '推理过程',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            message.reasoningContent!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  // 消息内容
                  message.isUser
                      ? Text(message.text, style: const TextStyle(fontSize: 16))
                      : FlutterMarkdownImpl(data: message.text),
                  // 状态提示文本
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
  }

  void _showMessageOptionMenu(ChatMessage message, BuildContext context) {
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            child: const Text('复制'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
              Navigator.pop(context); // 关闭菜单
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('删除'),
            onPressed: () {
              // 找到消息在列表中的索引
              final index = chatState.messages.indexOf(message);
              if (index != -1) {
                chatState.deleteMessagePair(index);
              }
              Navigator.pop(context);
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
      )
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
