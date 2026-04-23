import '../chat_message.dart';

/// Structured model-visible context item used before provider-specific encoding.
/// This preserves tool transcript semantics without forcing every upstream
/// stage to work directly with flattened chat text.
enum ModelContextItemType {
  systemMessage,
  userMessage,
  assistantMessage,
  assistantToolUse,
  userToolResult,
}

class ModelContextItem {
  final ModelContextItemType type;
  final String text;
  final DateTime? timestamp;
  final String? toolName;
  final Map<String, dynamic>? arguments;

  const ModelContextItem({
    required this.type,
    required this.text,
    this.timestamp,
    this.toolName,
    this.arguments,
  });

  factory ModelContextItem.systemMessage(
    String text, {
    DateTime? timestamp,
  }) {
    return ModelContextItem(
      type: ModelContextItemType.systemMessage,
      text: text,
      timestamp: timestamp,
    );
  }

  factory ModelContextItem.userMessage(
    String text, {
    DateTime? timestamp,
  }) {
    return ModelContextItem(
      type: ModelContextItemType.userMessage,
      text: text,
      timestamp: timestamp,
    );
  }

  factory ModelContextItem.assistantMessage(
    String text, {
    DateTime? timestamp,
  }) {
    return ModelContextItem(
      type: ModelContextItemType.assistantMessage,
      text: text,
      timestamp: timestamp,
    );
  }

  factory ModelContextItem.assistantToolUse({
    required String text,
    String? toolName,
    Map<String, dynamic>? arguments,
    DateTime? timestamp,
  }) {
    return ModelContextItem(
      type: ModelContextItemType.assistantToolUse,
      text: text,
      toolName: toolName,
      arguments: arguments,
      timestamp: timestamp,
    );
  }

  factory ModelContextItem.userToolResult({
    required String text,
    String? toolName,
    DateTime? timestamp,
  }) {
    return ModelContextItem(
      type: ModelContextItemType.userToolResult,
      text: text,
      toolName: toolName,
      timestamp: timestamp,
    );
  }

  MessageRole get messageRole {
    switch (type) {
      case ModelContextItemType.systemMessage:
        return MessageRole.system;
      case ModelContextItemType.userMessage:
      case ModelContextItemType.userToolResult:
        return MessageRole.user;
      case ModelContextItemType.assistantMessage:
      case ModelContextItemType.assistantToolUse:
        return MessageRole.assistant;
    }
  }
}
