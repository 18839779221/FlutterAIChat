import '../chat_message.dart';

/// Structured model-visible context item used before provider-specific encoding.
///
/// Assistant-side context (assistant text, tool_use) is no longer modeled here —
/// the carrier architecture (spec 2026-05-22) preserves provider assistant
/// turns verbatim via `RawAssistantCarrier`. This type now covers only the
/// "our-side" context: system prompts, user inputs, tool results.
enum ModelContextItemType {
  systemMessage,
  userMessage,
  userToolResult,
}

class ModelContextItem {
  final ModelContextItemType type;
  final String text;
  final DateTime? timestamp;
  final String? toolName;
  final String? providerCallId;

  const ModelContextItem({
    required this.type,
    required this.text,
    this.timestamp,
    this.toolName,
    this.providerCallId,
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

  factory ModelContextItem.userToolResult({
    required String text,
    String? toolName,
    String? providerCallId,
    DateTime? timestamp,
  }) {
    return ModelContextItem(
      type: ModelContextItemType.userToolResult,
      text: text,
      toolName: toolName,
      providerCallId: providerCallId,
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
    }
  }
}
