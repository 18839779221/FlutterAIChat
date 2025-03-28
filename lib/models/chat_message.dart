enum MessageRole {
  user,
  assistant,
  system
}

class ChatMessage {
  String text;
  final MessageRole role;
  final DateTime timestamp;
  final int? id;

  ChatMessage({
    required this.text,
    required this.role,
    this.id,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'role': role.toString().split('.').last,
      'timestamp': timestamp.millisecondsSinceEpoch,
      if (id != null) 'id': id,
    };
  }

  void appendText(String newText) {
    text += newText;
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      text: map['text'],
      role: MessageRole.values.firstWhere(
        (e) => e.toString().split('.').last == map['role'],
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }

  bool get isUser => role == MessageRole.user;
} 