import 'dart:convert';

import 'package:ai_chat/models/chat_message.dart';

enum ChatEventType {
  userMessage,
  contextCompacted,
  assistantPlannerMessage,
  assistantReasoningDelta,
  assistantTextDelta,
  assistantTextFinal,
  assistantToolCall,
  assistantToolConfirmation,
  assistantQuestionPrompt,
  assistantTurnSnapshot,
  toolExecutionStarted,
  toolResult,
  userInteractionResult,
  toolError,
  turnStatus,
  finalAnswer,
  error,
}

enum ChatEventUserMessageKind {
  start,
  followUp,
  systemReminder,
}

class ChatEvent {
  final int? id;
  final int turnId;
  final int groupId;
  final int sequence;
  final ChatEventType eventType;
  final MessageRole? role;
  final String? status;
  final String? content;
  final Map<String, dynamic>? payloadJson;
  final DateTime createdAt;

  ChatEvent({
    this.id,
    required this.turnId,
    required this.groupId,
    required this.sequence,
    required this.eventType,
    this.role,
    this.status,
    this.content,
    this.payloadJson,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  ChatEventUserMessageKind? get userMessageKind {
    final raw = payloadJson?['userMessageKind']?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return ChatEventUserMessageKind.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ChatEventUserMessageKind.start,
    );
  }

  ChatEvent copyWith({int? id}) {
    return ChatEvent(
      id: id ?? this.id,
      turnId: turnId,
      groupId: groupId,
      sequence: sequence,
      eventType: eventType,
      role: role,
      status: status,
      content: content,
      payloadJson: payloadJson,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'turn_id': turnId,
      'group_id': groupId,
      'sequence': sequence,
      'event_type': eventType.name,
      'role': role?.name,
      'status': status,
      'content': content,
      'payload_json': payloadJson == null ? null : jsonEncode(payloadJson),
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ChatEvent.fromMap(Map<String, dynamic> map) {
    return ChatEvent(
      id: map['id'] as int?,
      turnId: map['turn_id'] as int,
      groupId: map['group_id'] as int,
      sequence: map['sequence'] as int,
      eventType: ChatEventType.values.firstWhere(
        (value) => value.name == map['event_type'],
        orElse: () => ChatEventType.error,
      ),
      role: _parseRole(map['role']),
      status: map['status'] as String?,
      content: map['content'] as String?,
      payloadJson: _parsePayload(map['payload_json']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  static MessageRole? _parseRole(dynamic value) {
    if (value is! String) {
      return null;
    }

    return MessageRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => MessageRole.system,
    );
  }

  static Map<String, dynamic>? _parsePayload(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      return value.cast<String, dynamic>();
    }

    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }

    return null;
  }
}
