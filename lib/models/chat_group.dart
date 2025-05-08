class ChatGroup {
  int? id;
  String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final String? systemPrompt;

  ChatGroup({
    this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    this.systemPrompt,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastMessageAt = lastMessageAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_message_at': lastMessageAt.millisecondsSinceEpoch,
      'system_prompt': systemPrompt,
    };
  }

  factory ChatGroup.fromMap(Map<String, dynamic> map) {
    return ChatGroup(
      id: map['id'],
      title: map['title'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(map['last_message_at']),
      systemPrompt: map['system_prompt'],
    );
  }

  ChatGroup copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    String? systemPrompt,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }
} 