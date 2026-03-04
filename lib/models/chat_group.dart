class ChatGroup {
  int? id;
  String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final String? systemPrompt;
  final bool isSummarized;

  ChatGroup({
    this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    this.systemPrompt,
    this.isSummarized = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastMessageAt = lastMessageAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_message_at': lastMessageAt.millisecondsSinceEpoch,
      'system_prompt': systemPrompt,
      'is_summarized': isSummarized ? 1 : 0,
    };
  }

  factory ChatGroup.fromMap(Map<String, dynamic> map) {
    return ChatGroup(
      id: map['id'],
      title: map['title'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(map['last_message_at']),
      systemPrompt: map['system_prompt'],
      isSummarized: map['is_summarized'] == 1,
    );
  }

  ChatGroup copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    String? systemPrompt,
    bool? isSummarized,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isSummarized: isSummarized ?? this.isSummarized,
    );
  }
} 