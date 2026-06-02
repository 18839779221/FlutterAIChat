import 'package:path/path.dart' as path;

import 'agent_path.dart';
import 'agent_path_resolver.dart';
import 'file_tool_models.dart';
import 'file_tool_root_service.dart';

class FileToolPathPolicy {
  FileToolPathPolicy({
    required FileToolRootService rootService,
  })  : _rootService = rootService,
        _pathResolver = AgentPathResolver(rootService: rootService);

  final FileToolRootService _rootService;
  final AgentPathResolver _pathResolver;

  FileToolPathResolution normalizeSandboxPath(
    String rawPath, {
    required String cwd,
  }) {
    final sanitized = _sanitize(rawPath);
    final sanitizedCwd = _sanitize(cwd);
    if (sanitized == null || sanitizedCwd == null) {
      return const FileToolPathResolution.invalid(errorCode: 'empty_path');
    }
    try {
      final resolved = _pathResolver.resolvePath(sanitized, cwd: sanitizedCwd);
      final absolutePath = resolved.hostAbsolutePath;
      final rootPath = _rootService.rootPath;
      if (!(path.equals(absolutePath, rootPath) ||
          path.isWithin(rootPath, absolutePath))) {
        return const FileToolPathResolution.invalid(
          errorCode: 'path_outside_sandbox',
        );
      }
      return FileToolPathResolution.valid(
        agentPath: resolved.agentAbsolutePath,
        relativePath: resolved.relativePathFromRoot,
        absolutePath: resolved.hostAbsolutePath,
      );
    } on AgentPathEscapeException {
      return const FileToolPathResolution.invalid(
        errorCode: 'path_outside_sandbox',
      );
    }
  }

  FileToolPathResolution normalizeDirectoryPath(
    String? rawPath, {
    required String cwd,
  }) {
    final trimmed = rawPath?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == '.') {
      return FileToolPathResolution.valid(
        agentPath: '/',
        relativePath: '',
        absolutePath: _rootService.rootPath,
      );
    }
    return normalizeSandboxPath(trimmed, cwd: cwd);
  }

  String? _sanitize(String rawPath) {
    final trimmed = rawPath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.contains('\x00')) {
      return null;
    }
    return trimmed;
  }
}
