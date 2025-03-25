import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import 'code_block_builder.dart';

class ChatMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool isLoading;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return Align(
                  alignment: message.isUser 
                      ? Alignment.centerRight 
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: message.isUser 
                          ? Colors.blue[100] 
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12.0),
                    ),
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
                );
              },
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

