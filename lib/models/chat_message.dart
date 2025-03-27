import 'dart:convert';

class ChatMessage {
  String text;
  final bool isUser;

  ChatMessage({
    required this.text,
    required this.isUser,
  });

  void appendText(String newText) {
    text += newText;
  }
} 