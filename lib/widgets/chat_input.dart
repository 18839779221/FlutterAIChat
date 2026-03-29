import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_providers.dart';

class ChatInput extends ConsumerWidget {
  const ChatInput({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只监听需要的状态
    final useReasoning = ref.watch(useReasoningProvider);
    final useConciseMode = ref.watch(useConciseModeProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final textController = ref.watch(textControllerProvider);
    final focusNode = ref.watch(focusNodeProvider);

    final chatController = ref.read(chatControllerProvider);
    final bottomHomeHeight = MediaQuery.of(context).padding.bottom; // Home 栏高度
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom; // 键盘高度
    final isStreamingResponse = sendPhase == ChatSendPhase.streamingResponse;
    final isAwaitingConfirmation =
        sendPhase == ChatSendPhase.awaitingConfirmation;
    final isBlockingPhase = sendPhase == ChatSendPhase.preparing ||
        sendPhase == ChatSendPhase.executingTool ||
        sendPhase == ChatSendPhase.streamingResponse;
    final isComposerLocked = sendPhase != ChatSendPhase.idle;

    void submitCurrentInput() {
      if (isComposerLocked) {
        return;
      }

      final pendingText = textController.text;
      if (pendingText.trim().isEmpty) {
        return;
      }

      // 在点击发送的同一帧里先清空输入框，避免 Web 文本框在异步发送期间
      // 继续显示旧内容，造成“消息没有发出去”的错觉。
      textController.clear();
      chatController.sendMessage(pendingText);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: EdgeInsets.only(bottom: keyboardHeight > 0 ? 0 : bottomHomeHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 模式按钮行
          Row(
            children: [
              // 推理模式按钮
              TextButton(
                onPressed: () => chatController.setUseReasoning(!useReasoning),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: useReasoning 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  backgroundColor: useReasoning 
                      ? Theme.of(context).primaryColor.withOpacity(0.1) 
                      : Colors.transparent,
                ),
                child: Text(
                  '深度思考',
                  style: TextStyle(
                    color: useReasoning 
                        ? Theme.of(context).primaryColor 
                        : Colors.grey[600],
                    fontWeight: useReasoning ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 简洁模式按钮
              TextButton(
                onPressed: () => chatController.setUseConciseMode(!useConciseMode),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: useConciseMode 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  backgroundColor: useConciseMode 
                      ? Theme.of(context).primaryColor.withOpacity(0.1) 
                      : Colors.transparent,
                ),
                child: Text(
                  '简洁模式',
                  style: TextStyle(
                    color: useConciseMode 
                        ? Theme.of(context).primaryColor 
                        : Colors.grey[600],
                    fontWeight: useConciseMode ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 140, // 限制最大高度
                  ),
                  child: TextField(
                    focusNode: focusNode,
                    controller: textController,
                    enabled: !isComposerLocked,
                    maxLines: null, // 允许多行输入
                    textInputAction: TextInputAction.newline, // 回车键变为换行
                    keyboardType: TextInputType.multiline, // 多行输入键盘
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                    ),
                    onSubmitted: (text) {
                      submitCurrentInput();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 发送/取消按钮
              SizedBox(
                width: 48,
                height: 48,
                child: MaterialButton(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  color: Theme.of(context).primaryColor,
                  onPressed: () {
                    if (isStreamingResponse) {
                      chatController.cancelStreamSubscription();
                      return;
                    }

                    if (isBlockingPhase || isAwaitingConfirmation) {
                      return;
                    }

                    submitCurrentInput();
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isBlockingPhase
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            isAwaitingConfirmation
                                ? Icons.pending_actions
                                : Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
} 
