import 'message_content_type.dart';
import 'structured_card.dart';

/// Minimal payload wrapper that pairs a [MessageContentType] with optional data.
class MessagePayload {
  final MessageContentType contentType;
  final StructuredCard? card;
  final Map<String, dynamic>? toolData;

  const MessagePayload({
    this.contentType = MessageContentType.plainText,
    this.card,
    this.toolData,
  })  : assert(
          contentType != MessageContentType.structuredCard || card != null,
          'structuredCard payloads must include a card',
        ),
        assert(
          contentType != MessageContentType.toolResult || toolData != null,
          'toolResult payloads must include toolData',
        ),
        assert(
          contentType != MessageContentType.plainText || (card == null && toolData == null),
          'plainText payloads cannot carry structured or tool data',
        ),
        assert(
          contentType != MessageContentType.structuredCard || toolData == null,
          'structuredCard payloads cannot include tool data',
        ),
        assert(
          contentType != MessageContentType.toolResult || card == null,
          'toolResult payloads cannot include structured cards',
        );
}
