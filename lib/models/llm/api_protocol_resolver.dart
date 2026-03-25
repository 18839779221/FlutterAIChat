enum ApiStyle {
  chatCompletions,
  responses,
}

class ApiProtocolResolver {
  const ApiProtocolResolver();

  ApiStyle resolveStyle(String rawUrl) {
    final path = Uri.parse(rawUrl.trim()).path.toLowerCase();
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

    if (path.endsWith('/responses')) {
      return uri;
    }
    return uri.replace(path: '$path/responses');
  }
}
