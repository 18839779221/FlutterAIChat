import 'dart:convert';

import 'chat/chat_attachment.dart';
import 'package:ai_chat/models/response/message_content_type.dart';

enum MessageRole { user, assistant, system }

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
  String? reasoningContent; // 推理过程
  MessageContentType contentType;
  Map<String, dynamic>? payloadJson;
  Map<String, dynamic>? referenceJson;
  List<ChatAttachment> attachments;

  ChatMessage({
    required this.text,
    required this.role,
    this.id,
    DateTime? timestamp,
    this.status = MessageStatus.initial,
    this.reasoningContent,
    this.contentType = MessageContentType.plainText,
    this.payloadJson,
    this.referenceJson,
    this.attachments = const <ChatAttachment>[],
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'role': role.toString().split('.').last,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status.toString().split('.').last,
      'reasoning_content': reasoningContent,
      'content_type': contentType.wireName,
      'payload_json': _encodeJsonField(payloadJson),
      'reference_json': _encodeJsonField(referenceJson),
      if (id != null) 'id': id,
    };
  }

  void appendText(String newText) {
    text += newText;
  }

  void appendReasoning(String newReasoningContent) {
    reasoningContent = (reasoningContent ?? '') + newReasoningContent;
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
      reasoningContent: map['reasoning_content'],
      contentType: MessageContentTypeParsing.fromString(map['content_type']),
      payloadJson: _coerceJsonField(map['payload_json']),
      referenceJson: _coerceJsonField(map['reference_json']),
      attachments: const <ChatAttachment>[],
    );
  }

  bool get isUser => role == MessageRole.user;

  bool get isAssistant => role == MessageRole.assistant;

  // 添加copyWith方法以支持状态更新
  ChatMessage copyWith({
    String? text,
    MessageRole? role,
    DateTime? timestamp,
    int? id,
    MessageStatus? status,
    String? reasoningContent,
    MessageContentType? contentType,
    Map<String, dynamic>? payloadJson,
    Map<String, dynamic>? referenceJson,
    List<ChatAttachment>? attachments,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      role: role ?? this.role,
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      contentType: contentType ?? this.contentType,
      payloadJson: payloadJson ?? this.payloadJson,
      referenceJson: referenceJson ?? this.referenceJson,
      attachments: attachments ?? this.attachments,
    );
  }

  static Map<String, dynamic>? _coerceJsonField(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      return value.cast<String, dynamic>();
    }

    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.cast<String, dynamic>();
        }
      } catch (_) {
        // Ignore invalid JSON and fall through to null.
      }
    }

    return null;
  }

  static String? _encodeJsonField(Map<String, dynamic>? value) {
    if (value == null) {
      return null;
    }

    try {
      return jsonEncode(value);
    } catch (_) {
      return null;
    }
  }
}

int compareChatMessagesForTimeline(ChatMessage left, ChatMessage right) {
  final timestampComparison = left.timestamp.compareTo(right.timestamp);
  if (timestampComparison != 0) {
    return timestampComparison;
  }

  final leftId = left.id;
  final rightId = right.id;
  if (leftId != null && rightId != null) {
    return leftId.compareTo(rightId);
  }
  if (leftId != null) {
    return -1;
  }
  if (rightId != null) {
    return 1;
  }

  final roleComparison = _timelineRolePriority(left.role).compareTo(
    _timelineRolePriority(right.role),
  );
  if (roleComparison != 0) {
    return roleComparison;
  }

  final leftContentType = left.contentType.index.compareTo(right.contentType.index);
  if (leftContentType != 0) {
    return leftContentType;
  }

  final leftStatus = left.status.index.compareTo(right.status.index);
  if (leftStatus != 0) {
    return leftStatus;
  }

  final textComparison = left.text.compareTo(right.text);
  if (textComparison != 0) {
    return textComparison;
  }

  final leftReasoning = left.reasoningContent ?? '';
  final rightReasoning = right.reasoningContent ?? '';
  final reasoningComparison = leftReasoning.compareTo(rightReasoning);
  if (reasoningComparison != 0) {
    return reasoningComparison;
  }

  return 0;
}

int _timelineRolePriority(MessageRole role) {
  switch (role) {
    case MessageRole.user:
      return 0;
    case MessageRole.assistant:
      return 1;
    case MessageRole.system:
      return 2;
  }
}
