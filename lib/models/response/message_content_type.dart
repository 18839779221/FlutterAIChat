/// Defines the known content types for a chat message payload.
enum MessageContentType {
  plainText,
  structuredCard,
  toolInvocation,
  toolResult,
  actionConfirmation,
}

extension MessageContentTypeParsing on MessageContentType {
  static const MessageContentType _fallback = MessageContentType.plainText;

  /// Parses the serialized form of [MessageContentType] and falls back to
  /// [MessageContentType.plainText] when the value is missing or unrecognized.
  static MessageContentType fromString(String? value) {
    if (value == null || value.isEmpty) {
      return _fallback;
    }

    switch (value) {
      case 'structuredCard':
        return MessageContentType.structuredCard;
      case 'toolInvocation':
        return MessageContentType.toolInvocation;
      case 'toolResult':
        return MessageContentType.toolResult;
      case 'actionConfirmation':
        return MessageContentType.actionConfirmation;
      case 'plainText':
      default:
        return MessageContentType.plainText;
    }
  }

  /// Returns the wire form that can be stored in JSON or databases.
  String get wireName {
    switch (this) {
      case MessageContentType.plainText:
        return 'plainText';
      case MessageContentType.structuredCard:
        return 'structuredCard';
      case MessageContentType.toolInvocation:
        return 'toolInvocation';
      case MessageContentType.toolResult:
        return 'toolResult';
      case MessageContentType.actionConfirmation:
        return 'actionConfirmation';
    }
  }
}
