import 'chat_turn.dart';

class ChatGroup {
  int? id;
  String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final String? systemPrompt;
  final bool isSummarized;

  /// Provider style locked at group creation. A session may never switch
  /// providers — see spec 2026-05-22 (Policy A).
  final ChatTurnProviderStyle lockedProviderStyle;

  ChatGroup({
    this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    this.systemPrompt,
    this.isSummarized = false,
    required this.lockedProviderStyle,
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
      'locked_provider_style': lockedProviderStyle.name,
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
      lockedProviderStyle: ChatTurnProviderStyle.values.firstWhere(
        (e) => e.name == map['locked_provider_style'],
      ),
    );
  }

  ChatGroup copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    String? systemPrompt,
    bool? isSummarized,
    ChatTurnProviderStyle? lockedProviderStyle,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isSummarized: isSummarized ?? this.isSummarized,
      lockedProviderStyle: lockedProviderStyle ?? this.lockedProviderStyle,
    );
  }
}
