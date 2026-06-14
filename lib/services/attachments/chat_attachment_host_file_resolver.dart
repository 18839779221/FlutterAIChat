import 'dart:io';

import '../file_tools/agent_path_resolver.dart';
import '../file_tools/file_tool_root_service.dart';

/// Resolves attachment-local agent paths into host-visible files.
class ChatAttachmentHostFileResolver {
  ChatAttachmentHostFileResolver({
    required FileToolRootService rootService,
  }) : _pathResolver = AgentPathResolver(rootService: rootService);

  final AgentPathResolver _pathResolver;

  File? resolve(String? localPath) {
    final trimmed = localPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('file://')) {
      return File(Uri.parse(trimmed).toFilePath());
    }
    if (trimmed.startsWith('/')) {
      if (trimmed.startsWith('/workspaces/') ||
          trimmed.startsWith('/artifacts/') ||
          trimmed.startsWith('/tmp/') ||
          trimmed.startsWith('/memories/')) {
        final resolution = _pathResolver.resolvePath(trimmed, cwd: '/');
        return File(resolution.hostAbsolutePath);
      }
      return File(trimmed);
    }
    return File(trimmed);
  }
}
