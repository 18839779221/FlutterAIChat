import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.title});
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ChatService _chatService = ChatService();
  bool _isLoading = false;
  StreamSubscription? _streamSubscription;

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(text: text, isUser: true);
    final aiMessage = ChatMessage(text: '', isUser: false);
    
    setState(() {
      _messages.add(userMessage);
      _messages.add(aiMessage);
      _isLoading = true;
    });
    
    try {
      await _streamSubscription?.cancel();
      
      _streamSubscription = _chatService
          .sendMessageStream(text)
          .listen(
            (content) {
              setState(() {
                aiMessage.appendText(content);
              });
            },
            onError: (error) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('错误: $error')),
              );
              setState(() {
                _isLoading = false;
              });
            },
            onDone: () {
              setState(() {
                _isLoading = false;
              });
            },
          );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      setState(() {
        _isLoading = false;
      });
    }
    
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          ChatMessageList(
            messages: _messages,
            isLoading: _isLoading,
          ),
          ChatInput(
            controller: _textController,
            onSendMessage: _sendMessage,
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _streamSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }
} 