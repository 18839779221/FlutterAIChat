import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {

  final FocusNode focusNode;
  final TextEditingController controller;
  final Function(String) onSendMessage;
  final bool isGenerating; // 添加生成状态参数
  final VoidCallback onCancel; // 添加取消回调
  final bool useReasoning;
  final ValueChanged<bool> onReasoningChanged;

  const ChatInput({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.onSendMessage,
    this.isGenerating = false,
    required this.onCancel,
    required this.useReasoning,
    required this.onReasoningChanged,
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
      padding: const EdgeInsets.all(8.0),
      margin: EdgeInsets.only(bottom: keyboardHeight > 0 ? 0 : bottomHomeHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 推理模式按钮
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
              child: TextButton(
                onPressed: () => onReasoningChanged(!useReasoning),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 140, // 限制最大高度
                  ),
                  child:
                      // 输入框
                       TextField(
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
        ],
      ),
    );
  }
} 