import 'package:path/path.dart' as path;

import 'file_tool_models.dart';
import 'file_tool_root_service.dart';

class FileToolPathPolicy {
  FileToolPathPolicy({
    required FileToolRootService rootService,
  }) : _rootService = rootService;

  final FileToolRootService _rootService;

  FileToolPathResolution normalizeSandboxPath(String rawPath) {
    final sanitized = _sanitize(rawPath);
    if (sanitized == null) {
      return const FileToolPathResolution.invalid(errorCode: 'empty_path');
    }

    if (path.isAbsolute(sanitized)) {
      return const FileToolPathResolution.invalid(
        errorCode: 'absolute_path_not_allowed',
      );
    }

    final normalizedRelative = path.normalize(sanitized);
    if (normalizedRelative == '.' || normalizedRelative == '..') {
      return const FileToolPathResolution.invalid(errorCode: 'empty_path');
    }
    if (_escapesSandbox(normalizedRelative)) {
      return const FileToolPathResolution.invalid(
        errorCode: 'path_outside_sandbox',
      );
    }

    final absolutePath =
        path.normalize(path.join(_rootService.rootPath, normalizedRelative));
    final rootPath = _rootService.rootPath;
    if (!(path.equals(absolutePath, rootPath) ||
        path.isWithin(rootPath, absolutePath))) {
      return const FileToolPathResolution.invalid(
        errorCode: 'path_outside_sandbox',
      );
    }

    return FileToolPathResolution.valid(
      relativePath: normalizedRelative,
      absolutePath: absolutePath,
    );
  }

  FileToolPathResolution normalizeDirectoryPath(String? rawPath) {
    final trimmed = rawPath?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == '.') {
      return FileToolPathResolution.valid(
        relativePath: '',
        absolutePath: _rootService.rootPath,
      );
    }
    return normalizeSandboxPath(trimmed);
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

  bool _escapesSandbox(String relativePath) {
    return relativePath.startsWith('../') || relativePath.contains('/../');
  }
}
