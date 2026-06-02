import 'dart:io';

import 'package:path/path.dart' as path;

class FileToolRootService {
  FileToolRootService({
    required Directory rootDirectory,
  }) : _rootDirectory = rootDirectory;

  final Directory _rootDirectory;

  String get rootPath => path.normalize(_rootDirectory.path);

  Directory get rootDirectory => Directory(rootPath);

  Future<void> ensureReady() {
    return rootDirectory.create(recursive: true);
  }

  String resolveHostPath(String relativePathFromRoot) {
    if (relativePathFromRoot.trim().isEmpty) {
      return rootPath;
    }
    return path.normalize(path.join(rootPath, relativePathFromRoot));
  }

  File resolveFile(String relativePath) {
    return File(resolveHostPath(relativePath));
  }

  Directory resolveDirectory(String relativePath) {
    if (relativePath.trim().isEmpty) {
      return rootDirectory;
    }
    return Directory(resolveHostPath(relativePath));
  }
}
