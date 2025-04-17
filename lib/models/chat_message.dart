enum MessageRole {
  user,
  assistant,
  system
}

enum MessageStatus {
  // 初始状态
  initial,
  // 正在生成
  generating,
  // 生成完成
  completed,
  // 生成被中断
  interrupted,
  // 生成失败
  failed
}

class ChatMessage {
  String text;
  final MessageRole role;
  final DateTime timestamp;
  int? id;
  MessageStatus status;

  ChatMessage({
    required this.text,
    required this.role,
    this.id,
    DateTime? timestamp,
    this.status = MessageStatus.initial,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'role': role.toString().split('.').last,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status.toString().split('.').last,
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
      status: MessageStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (map['status'] ?? 'initial'),
        orElse: () => MessageStatus.initial,
      ),
    );
  }

  bool get isUser => role == MessageRole.user;
} 