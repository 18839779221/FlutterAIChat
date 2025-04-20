import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {

  final FocusNode focusNode;
  final TextEditingController controller;
  final Function(String) onSendMessage;
  final bool isGenerating; // 添加生成状态参数
  final VoidCallback onCancel; // 添加取消回调

  const ChatInput({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.onSendMessage,
    this.isGenerating = false,
    required this.onCancel,
  });

  void _handleSubmit() {
    if (isGenerating) {
      onCancel();
    } else {
      final text = controller.text;
      if (text.trim().isNotEmpty) {
        onSendMessage(text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomHomeHeight = MediaQuery.of(context).padding.bottom; // Home 栏高度
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom; // 键盘高度

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      padding: const EdgeInsets.all(8.0),
      margin: EdgeInsets.only(bottom: keyboardHeight > 0 ? 0 : bottomHomeHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, // 将发送按钮对齐到底部
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(
                maxHeight: 140, // 限制最大高度
              ),
              child:
                  // 输入框
                  Expanded(
                    child: TextField(
                      focusNode: focusNode,
                      controller: controller,
                      maxLines: null, // 允许多行输入
                      textInputAction: TextInputAction.newline, // 回车键变为换行
                      keyboardType: TextInputType.multiline, // 多行输入键盘
                      decoration: const InputDecoration(
                        hintText: '输入消息...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (text) {
                        if (text.trim().isNotEmpty) {
                          onSendMessage(text);
                        }
                      },
                    ),
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
              onPressed: _handleSubmit,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 