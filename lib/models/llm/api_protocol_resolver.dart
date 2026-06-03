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
    return detectExplicitStyle(rawUrl) ?? ApiStyle.responses;
  }

  ApiStyle? detectExplicitStyle(String rawUrl) {
    final path = _normalizedPath(Uri.parse(rawUrl.trim()).path).toLowerCase();
    if (path.endsWith('/v1/messages')) {
      return ApiStyle.anthropicMessages;
    }
    if (path.endsWith('/chat/completions')) {
      return ApiStyle.chatCompletions;
    }
    if (path.endsWith('/responses')) {
      return ApiStyle.responses;
    }
    return null;
  }

  Uri buildRequestUri(String rawUrl, ApiStyle style) {
    final uri = Uri.parse(rawUrl.trim());
    final explicitStyle = detectExplicitStyle(rawUrl);
    if (explicitStyle == style) {
      return uri.replace(path: _normalizedPath(uri.path));
    }
    final path = _basePathWithoutEndpoint(uri.path);

    if (style == ApiStyle.chatCompletions) {
      return uri.replace(path: _appendPath(path, '/chat/completions'));
    }

    if (style == ApiStyle.anthropicMessages) {
      return uri.replace(path: _appendPath(path, '/v1/messages'));
    }

    return uri.replace(path: _appendPath(path, '/responses'));
  }

  Uri buildModelsUri(String rawUrl) {
    final uri = Uri.parse(rawUrl.trim());
    final path = _basePathWithoutEndpoint(uri.path);
    return uri.replace(path: _appendPath(path, '/models'));
  }

  String _basePathWithoutEndpoint(String rawPath) {
    final path = _normalizedPath(rawPath);
    if (path.endsWith('/chat/completions')) {
      return path.substring(0, path.length - '/chat/completions'.length);
    }
    if (path.endsWith('/v1/messages')) {
      return path.substring(0, path.length - '/messages'.length);
    }
    if (path.endsWith('/responses')) {
      return path.substring(0, path.length - '/responses'.length);
    }
    return path;
  }

  String _normalizedPath(String rawPath) {
    if (rawPath == '/') {
      return '';
    }
    if (rawPath.endsWith('/') && rawPath.length > 1) {
      return rawPath.substring(0, rawPath.length - 1);
    }
    return rawPath;
  }

  String _appendPath(String basePath, String suffix) {
    final normalizedBase = _normalizedPath(basePath);
    if (normalizedBase.isEmpty) {
      return suffix;
    }
    return '$normalizedBase$suffix';
  }
}
