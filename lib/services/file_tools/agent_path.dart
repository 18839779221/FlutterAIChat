class AgentPathEscapeException implements Exception {
  AgentPathEscapeException(this.rawPath);

  final String rawPath;

  @override
  String toString() => 'AgentPathEscapeException($rawPath)';
}

class AgentPath {
  AgentPath._(this.value);

  final String value;

  factory AgentPath.absolute(String path) {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'Agent path must be absolute.');
    }
    return AgentPath._(path);
  }

  @override
  String toString() => value;
}

class AgentPathResolution {
  const AgentPathResolution({
    required this.agentPath,
    required this.relativePathFromRoot,
    required this.hostAbsolutePath,
  });

  final AgentPath agentPath;
  final String relativePathFromRoot;
  final String hostAbsolutePath;

  String get agentAbsolutePath => agentPath.value;
}
