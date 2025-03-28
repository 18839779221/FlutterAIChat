
class ChatMessage {
  final int? id;
  String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  void appendText(String newText) {
    text += newText;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser ? 1 : 0,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      text: map['text'],
      isUser: map['isUser'] == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
} 