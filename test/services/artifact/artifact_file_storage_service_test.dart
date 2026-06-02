import 'dart:io';

import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactFileStorageService', () {
    test('writes and reads a default-workspace artifact file path', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'artifact-storage-',
      );
      final service = ArtifactFileStorageService(rootDirectory: tempDirectory);

      final saved = await service.saveArtifactSource(
        groupId: 7,
        artifactId: 'portfolio-pie',
        title: '投资组合饼图',
        type: ArtifactType.html,
        source: '<div>hello</div>',
      );

      expect(
        saved.sourcePath,
        '/workspaces/.default/artifacts/portfolio-pie.html',
      );
      final content = await service.readArtifactSource(saved.sourcePath);
      expect(content, '<div>hello</div>');

      await tempDirectory.delete(recursive: true);
    });

    test('writes explicit-workspace artifacts under that workspace root',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'artifact-storage-explicit-',
      );
      final service = ArtifactFileStorageService(
        rootDirectory: tempDirectory,
        workspaceIdResolver: (_) async => 'ws_20260602_a3k9qx',
      );

      final saved = await service.saveArtifactSource(
        groupId: 7,
        artifactId: 'portfolio-pie',
        title: '投资组合饼图',
        type: ArtifactType.html,
        source: '<div>hello</div>',
      );

      expect(
        saved.sourcePath,
        '/workspaces/ws_20260602_a3k9qx/artifacts/portfolio-pie.html',
      );
      final content = await service.readArtifactSource(saved.sourcePath);
      expect(content, '<div>hello</div>');

      await tempDirectory.delete(recursive: true);
    });
  });
}
