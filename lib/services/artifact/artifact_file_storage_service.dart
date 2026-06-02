import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/artifact/artifact_create_result.dart';
import '../../models/artifact/artifact_type.dart';
import '../workspace/workspace_binding_service.dart';

typedef ArtifactWorkspaceIdResolver = Future<String?> Function(int groupId);

/// Stores inline artifact files under a stable per-group path.
class ArtifactFileStorageService {
  ArtifactFileStorageService({
    required Directory rootDirectory,
    ArtifactWorkspaceIdResolver? workspaceIdResolver,
    WorkspaceBindingService? workspaceBindingService,
  })  : _rootDirectory = rootDirectory,
        _workspaceIdResolver = workspaceIdResolver ?? _defaultWorkspaceIdResolver,
        _workspaceBindingService =
            workspaceBindingService ?? WorkspaceBindingService();

  final Directory _rootDirectory;
  final ArtifactWorkspaceIdResolver _workspaceIdResolver;
  final WorkspaceBindingService _workspaceBindingService;

  Directory get rootDirectory => _rootDirectory;

  Future<void> ensureReady() {
    return rootDirectory.create(recursive: true);
  }

  String relativePathFor({
    required String workspaceId,
    required String artifactId,
    required ArtifactType type,
  }) {
    final extension = type == ArtifactType.svg ? 'svg' : 'html';
    return path.posix.join(
      '/workspaces',
      workspaceId,
      'artifacts',
      '$artifactId.$extension',
    );
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
    final workspaceId = _workspaceBindingService
        .resolveWorkspaceId(await _workspaceIdResolver(groupId))
        .workspaceId;
    final relativePath = relativePathFor(
      workspaceId: workspaceId,
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

  static Future<String?> _defaultWorkspaceIdResolver(int groupId) async {
    return null;
  }
}
