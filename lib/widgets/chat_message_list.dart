import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/markdown/markdown_widget_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/chat_message.dart';

class ChatMessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isLoading;
  final FocusNode inputFocusNode;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.isLoading,
    required this.inputFocusNode,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final ScrollController _scrollController = ScrollController();
  // 是否快滑到了底部
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final isNearBottom = (maxScroll - currentScroll) <= 100;
    
    if (_isNearBottom != isNearBottom) {
      setState(() {
        _isNearBottom = isNearBottom;
      });
    }

    final scrollingPosition = _scrollController.position;
    // 用户向下滑动，且不是惯性滑动时收起输入框
    if (scrollingPosition.userScrollDirection == ScrollDirection.reverse
    && scrollingPosition.activity is DragScrollActivity) {
      widget.inputFocusNode.unfocus();
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
    if (widget.isLoading) {
      _scrollToBottom();
    }
    
    return Expanded(
      child: Stack(
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
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final message = widget.messages[index];
                return Align(
                  alignment: message.isUser 
                      ? Alignment.centerRight 
                      : Alignment.centerLeft,
                  child: _buildMessageItem(message),
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
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message) {
    return Container(
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
                    ? SelectableText(message.text)
                    // : MarkdownWidgetImpl(data: message.text),
                    : FlutterMarkdownImpl(data: message.text),
                // 状态提示文本
                if (!message.isUser && message.status != MessageStatus.completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _getStatusText(message.status),
                      style: TextStyle(
                        fontSize: 10,
                        color: _getStatusColor(message.status)
                            .withOpacity(0.8),
                      ),
                    ),
                  ),
              ],
            ),
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

