import 'package:path/path.dart' as path;

import 'agent_path.dart';
import 'file_tool_root_service.dart';

class AgentPathResolver {
  AgentPathResolver({
    required FileToolRootService rootService,
  }) : _rootService = rootService;

  final FileToolRootService _rootService;

  AgentPathResolution resolvePath(
    String rawPath, {
    required String cwd,
  }) {
    final sanitizedPath = _sanitize(rawPath);
    final sanitizedCwd = _sanitize(cwd);
    if (sanitizedPath == null || sanitizedCwd == null) {
      throw ArgumentError('Path and cwd must not be empty.');
    }

    final normalizedCwd = _normalizeAbsolute(sanitizedCwd);
    final candidate = sanitizedPath.startsWith('/')
        ? sanitizedPath
        : path.posix.join(normalizedCwd, sanitizedPath);
    final normalizedAgentPath = _normalizeAbsolute(candidate);
    final relativePath = normalizedAgentPath == '/'
        ? ''
        : normalizedAgentPath.substring(1);

    return AgentPathResolution(
      agentPath: AgentPath.absolute(normalizedAgentPath),
      relativePathFromRoot: relativePath,
      hostAbsolutePath: _rootService.resolveHostPath(relativePath),
    );
  }

  String? _sanitize(String rawPath) {
    final trimmed = rawPath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty || trimmed.contains('\x00')) {
      return null;
    }
    return trimmed;
  }

  String _normalizeAbsolute(String rawPath) {
    final candidate = rawPath.startsWith('/') ? rawPath : '/$rawPath';
    final segments = <String>[];
    for (final segment in candidate.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isEmpty) {
          throw AgentPathEscapeException(rawPath);
        }
        segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      return '/';
    }
    return '/${segments.join('/')}';
  }
}
