import '../models/chat_message.dart';
import '../models/chat/chat_attachment.dart';
import '../models/context/model_context_item.dart';
import '../utils/logger.dart';

/// Encodes structured context items into ChatMessage objects consumed by the
/// current LLM interfaces. This keeps transcript structure explicit in the
/// application layer while preserving compatibility with existing providers.
class ModelContextItemEncoder {
  const ModelContextItemEncoder();

  static const _tag = 'ModelContextItemEncoder';

  List<ChatMessage> encodeAll(List<ModelContextItem> items) {
    return items
        .map(encode)
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  ChatMessage? encode(
    ModelContextItem item, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) {
    final encodedText = _encodeText(item).trim();
    if (encodedText.isEmpty) {
      return null;
    }

    if (item.type == ModelContextItemType.userMessage) {
      Logger.temp(
        _tag,
        'attachments.context_item_encoded',
        reason: 'diagnose_image_attachment_context_chain',
        data: {
          'contextType': item.type.name,
          'attachmentCount': attachments.length,
          'localIds': attachments.map((attachment) => attachment.localId).toList(),
          'hasProviderDataUrl': attachments
              .map(
                (attachment) =>
                    attachment.providerFileRefJson?['data_url'] is String &&
                    (attachment.providerFileRefJson?['data_url'] as String)
                        .trim()
                        .isNotEmpty,
              )
              .toList(),
          'textLength': encodedText.length,
        },
      );
    }

    return ChatMessage(
      text: encodedText,
      role: item.messageRole,
      timestamp: item.timestamp,
      status: MessageStatus.completed,
      attachments: attachments,
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
