import 'message_content_type.dart';

/// Minimal payload wrapper that pairs a [MessageContentType] with optional data.
class MessagePayload {
  final MessageContentType contentType;
  final Map<String, dynamic>? toolData;

  const MessagePayload({
    this.contentType = MessageContentType.plainText,
    this.toolData,
  })  : assert(
          contentType != MessageContentType.toolResult || toolData != null,
          'toolResult payloads must include toolData',
        ),
        assert(
          contentType != MessageContentType.plainText || toolData == null,
          'plainText payloads cannot carry tool data',
        );
}
