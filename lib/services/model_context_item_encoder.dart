import '../models/chat_message.dart';
import '../models/context/model_context_item.dart';

/// Encodes structured context items into ChatMessage objects consumed by the
/// current LLM interfaces. This keeps transcript structure explicit in the
/// application layer while preserving compatibility with existing providers.
class ModelContextItemEncoder {
  const ModelContextItemEncoder();

  List<ChatMessage> encodeAll(List<ModelContextItem> items) {
    return items
        .map(encode)
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  ChatMessage? encode(ModelContextItem item) {
    final encodedText = _encodeText(item).trim();
    if (encodedText.isEmpty) {
      return null;
    }

    return ChatMessage(
      text: encodedText,
      role: item.messageRole,
      timestamp: item.timestamp,
      status: MessageStatus.completed,
      payloadJson: {
        'modelContextType': item.type.name,
        if (item.toolName != null) 'toolName': item.toolName,
        if (item.providerCallId != null) 'providerCallId': item.providerCallId,
      },
    );
  }

  String _encodeText(ModelContextItem item) {
    switch (item.type) {
      case ModelContextItemType.systemMessage:
      case ModelContextItemType.userMessage:
        return item.text;
      case ModelContextItemType.userToolResult:
        return '[user tool_result] ${item.text.trim()}';
    }
  }
}
