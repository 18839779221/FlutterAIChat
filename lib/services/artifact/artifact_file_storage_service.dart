import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/artifact/artifact_create_result.dart';
import '../../models/artifact/artifact_type.dart';

/// Stores inline artifact files under a stable per-group path.
class ArtifactFileStorageService {
  ArtifactFileStorageService({
    required Directory rootDirectory,
  }) : _rootDirectory = rootDirectory;

  final Directory _rootDirectory;

  Directory get rootDirectory => _rootDirectory;

  Future<void> ensureReady() {
    return rootDirectory.create(recursive: true);
  }

  String relativePathFor({
    required int groupId,
    required String artifactId,
    required ArtifactType type,
  }) {
    final extension = type == ArtifactType.svg ? 'svg' : 'html';
    return path.posix.join('/artifacts', '$groupId', '$artifactId.$extension');
  }

  Future<ArtifactCreateResult> saveArtifactSource({
    required int groupId,
    required String artifactId,
    required String title,
    required ArtifactType type,
    required String source,
    List<String> warnings = const <String>[],
  }) async {
    await ensureReady();
    final relativePath = relativePathFor(
      groupId: groupId,
      artifactId: artifactId,
      type: type,
    );
    final file = File(path.join(rootDirectory.path, relativePath.substring(1)));
    await file.parent.create(recursive: true);
    await file.writeAsString(source, flush: true);

    return ArtifactCreateResult(
      artifactId: artifactId,
      title: title,
      type: type,
      sourcePath: relativePath,
      bytes: source.codeUnits.length,
      warnings: warnings,
    );
  }

  Future<String> readArtifactSource(String relativePath) {
    final normalized = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return File(path.join(rootDirectory.path, normalized)).readAsString();
  }

  String readArtifactSourceSync(String relativePath) {
    final normalized = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return File(path.join(rootDirectory.path, normalized)).readAsStringSync();
  }
}
