import 'chat_turn.dart';

const Object _unsetWorkspaceId = Object();

class ChatGroup {
  int? id;
  String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final String? systemPrompt;
  final bool isSummarized;
  final String? workspaceId;

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
    this.workspaceId,
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
      'workspace_id': workspaceId,
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
      workspaceId: map['workspace_id'] as String?,
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
    Object? workspaceId = _unsetWorkspaceId,
    ChatTurnProviderStyle? lockedProviderStyle,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isSummarized: isSummarized ?? this.isSummarized,
      workspaceId: identical(workspaceId, _unsetWorkspaceId)
          ? this.workspaceId
          : workspaceId as String?,
      lockedProviderStyle: lockedProviderStyle ?? this.lockedProviderStyle,
    );
  }
}
