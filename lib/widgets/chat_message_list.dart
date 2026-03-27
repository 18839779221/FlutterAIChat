import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../models/response/message_content_type.dart';
import '../models/response/structured_summary_card.dart';
import '../models/tool/tool_result.dart';
import '../providers/chat_providers.dart';
import 'structured_message/structured_summary_card_widget.dart';

class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({super.key});

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  // 是否快滑到了底部
  bool _isNearBottom = true;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // 初始化时监听滚动控制器
    _scrollController = ref.read(scrollControllerProvider);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    // 销毁时移除监听
    _scrollController.removeListener(_scrollListener);
    super.dispose();
  }

  void _scrollListener() {
    // 获取滚动控制器
    final scrollController = ref.read(scrollControllerProvider);
    final currentScroll = scrollController.offset;
    final isNearBottom = currentScroll <= 100;

    if (_isNearBottom != isNearBottom) {
      setState(() {
        _isNearBottom = isNearBottom;
      });
    }

    final scrollingPosition = scrollController.position;
    // 用户向下滑动，且不是惯性滑动时收起输入框
    if (scrollingPosition.userScrollDirection == ScrollDirection.reverse &&
        scrollingPosition.activity is DragScrollActivity) {
      ref.read(focusNodeProvider).unfocus();
    }
  }

  void _scrollToBottom() {
    final scrollController = ref.read(scrollControllerProvider);
    scrollController.animateTo(
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

  @override
  Widget build(BuildContext context) {
    // 获取所需状态
    final messages = ref.watch(messagesProvider);
    final isGenerating = ref.watch(isGeneratingProvider);
    final autoScrollToBottom = ref.watch(autoScrollToBottomProvider);
    final hasMoreMessages = ref.watch(hasMoreMessagesProvider);
    final scrollController = ref.watch(scrollControllerProvider);

    // 如果正在生成且允许自动滚动，则滚动到底部
    if (isGenerating && autoScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
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
            controller: scrollController,
            padding: const EdgeInsets.all(8.0),
            reverse: true,
            itemCount: messages.length + (hasMoreMessages ? 1 : 0),
            itemBuilder: (context, index) {
              if (hasMoreMessages && index >= messages.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final message = messages[index];
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
    );
  }

  Widget _buildMessageItem(ChatMessage message) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: GestureDetector(
        onLongPress: () {
          _showMessageOptionMenu(message);
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
                border:
                    !message.isUser && message.status != MessageStatus.completed
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
                  if (!message.isUser &&
                      message.reasoningContent != null &&
                      message.reasoningContent!.isNotEmpty)
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
                      : _buildAssistantMessageContent(message),
                  // 状态提示文本
                  if (!message.isUser &&
                      message.status != MessageStatus.completed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _getStatusText(message.status),
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              _getStatusColor(message.status).withOpacity(0.8),
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

  Widget _buildAssistantMessageContent(ChatMessage message) {
    switch (message.contentType) {
      case MessageContentType.plainText:
        return FlutterMarkdownImpl(data: message.text);
      case MessageContentType.structuredCard:
        final payload = message.payloadJson;
        if (payload == null) {
          return Text(message.text, style: const TextStyle(fontSize: 16));
        }

        try {
          final card = StructuredSummaryCard.fromJson(payload);
          return StructuredSummaryCardWidget(card: card);
        } catch (_) {
          return Text(message.text, style: const TextStyle(fontSize: 16));
        }
      case MessageContentType.toolResult:
        final payload = message.payloadJson;
        if (payload == null) {
          return Text(message.text, style: const TextStyle(fontSize: 16));
        }

        try {
          final toolResult = ToolResult.fromJson(payload);
          if (toolResult.toolName.isEmpty || toolResult.displayText.isEmpty) {
            return Text(message.text, style: const TextStyle(fontSize: 16));
          }

          final matchCount = toolResult.payload['matchCount'];
          final secondaryText = matchCount is int
              ? '找到 $matchCount 条历史消息'
              : toolResult.status == ToolExecutionStatus.failure
                  ? '工具执行失败'
                  : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                toolResult.displayText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (secondaryText != null) ...[
                const SizedBox(height: 4),
                Text(
                  secondaryText,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ],
          );
        } catch (_) {
          return Text(message.text, style: const TextStyle(fontSize: 16));
        }
    }
  }

  void _showMessageOptionMenu(ChatMessage message) {
    final messagesNotifier = ref.read(messagesProvider.notifier);
    final shouldShowStructuredDebugAction = kDebugMode &&
        message.isAssistant &&
        message.status == MessageStatus.completed &&
        message.contentType == MessageContentType.plainText;

    showCupertinoModalPopup(
        context: context,
        builder: (context) => CupertinoActionSheet(
              actions: [
                if (shouldShowStructuredDebugAction)
                  CupertinoActionSheetAction(
                    child: const Text('结构化整理（调试）'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await ref
                          .read(chatControllerProvider)
                          .structureMessageForDebug(message);
                    },
                  ),
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
                    final messages = ref.read(messagesProvider);
                    final index = messages.indexOf(message);
                    if (index != -1) {
                      messagesNotifier.deleteMessagePair(index);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                child: const Text('取消'),
                onPressed: () => Navigator.pop(context),
              ),
            ));
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
