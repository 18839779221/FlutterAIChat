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

  File resolveFile(String relativePath) {
    return File(path.join(rootPath, relativePath));
  }

  Directory resolveDirectory(String relativePath) {
    if (relativePath.trim().isEmpty) {
      return rootDirectory;
    }
    return Directory(path.join(rootPath, relativePath));
  }
}
