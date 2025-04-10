import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {

  final FocusNode focusNode;
  final TextEditingController controller;
  final Function(String) onSendMessage;

  const ChatInput({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.onSendMessage,
  });

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
        children: [
          Expanded(
            child: TextField(
              focusNode: focusNode,
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: InputBorder.none,
              ),
              onSubmitted: onSendMessage,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => onSendMessage(controller.text),
          ),
        ],
      ),
    );
  }
} 