import 'package:ai_chat/models/chat_turn.dart';

enum ApiStyle {
  chatCompletions,
  responses,
  anthropicMessages,
}

extension ApiStyleChatTurnProviderStyle on ApiStyle {
  ChatTurnProviderStyle toChatTurnProviderStyle() {
    switch (this) {
      case ApiStyle.chatCompletions:
        return ChatTurnProviderStyle.openaiChatCompletions;
      case ApiStyle.responses:
        return ChatTurnProviderStyle.openaiResponses;
      case ApiStyle.anthropicMessages:
        return ChatTurnProviderStyle.anthropicMessages;
    }
  }
}

class ApiProtocolResolver {
  const ApiProtocolResolver();

  ApiStyle resolveStyle(String rawUrl) {
    final path = Uri.parse(rawUrl.trim()).path.toLowerCase();
    if (path.endsWith('/v1/messages')) {
      return ApiStyle.anthropicMessages;
    }
    if (path.endsWith('/chat/completions')) {
      return ApiStyle.chatCompletions;
    }
    return ApiStyle.responses;
  }

  Uri buildRequestUri(String rawUrl, ApiStyle style) {
    final uri = Uri.parse(rawUrl.trim());
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;

    if (style == ApiStyle.chatCompletions) {
      if (path.endsWith('/chat/completions')) {
        return uri;
      }
      return uri.replace(path: '$path/chat/completions');
    }

    if (style == ApiStyle.anthropicMessages) {
      if (path.endsWith('/v1/messages')) {
        return uri;
      }
      return uri.replace(path: '$path/v1/messages');
    }

    if (path.endsWith('/responses')) {
      return uri;
    }
    return uri.replace(path: '$path/responses');
  }
}
