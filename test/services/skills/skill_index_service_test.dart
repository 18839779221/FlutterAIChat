import 'dart:io';

import 'package:ai_chat/services/skills/skill_frontmatter_parser.dart';
import 'package:ai_chat/services/skills/skill_index_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillIndexService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('skill-index-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns empty when installed directory has no skills', () async {
      final storage = SkillStorageService(
        rootDirectoryProvider: () async => tempDir,
      );
      final service = SkillIndexService(
        storageService: storage,
        frontmatterParser: const SkillFrontmatterParser(),
      );

      final result = await service.loadIndex();

      expect(result.descriptors, isEmpty);
      expect(result.invalidRecords, isEmpty);
    });

    test('loads a valid skill descriptor and marks it enabled by default',
        () async {
      final storage = SkillStorageService(
        rootDirectoryProvider: () async => tempDir,
      );
      final installedDir = await storage.installedSkillsDirectory();
      final skillDir = Directory('${installedDir.path}/edge-to-edge');
      await skillDir.create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: edge-to-edge
description: Improve Android edge-to-edge handling.
---
# Overview
Use Android edge-to-edge guidance.
''');

      final service = SkillIndexService(
        storageService: storage,
        frontmatterParser: const SkillFrontmatterParser(),
      );

      final result = await service.loadIndex();

      expect(result.descriptors, hasLength(1));
      expect(result.descriptors.single.id, 'edge-to-edge');
      expect(result.descriptors.single.name, 'edge-to-edge');
      expect(result.descriptors.single.description,
          'Improve Android edge-to-edge handling.');
      expect(result.descriptors.single.isEnabled, isTrue);
      expect(result.invalidRecords, isEmpty);
    });

    test('records a directory without SKILL.md as invalid', () async {
      final storage = SkillStorageService(
        rootDirectoryProvider: () async => tempDir,
      );
      final installedDir = await storage.installedSkillsDirectory();
      await Directory('${installedDir.path}/broken-skill').create(
        recursive: true,
      );

      final service = SkillIndexService(
        storageService: storage,
        frontmatterParser: const SkillFrontmatterParser(),
      );

      final result = await service.loadIndex();

      expect(result.descriptors, isEmpty);
      expect(result.invalidRecords, hasLength(1));
      expect(result.invalidRecords.single.skillId, 'broken-skill');
      expect(result.invalidRecords.single.status.name, 'invalid');
    });

    test('uses a stable normalized id when frontmatter name differs', () async {
      final storage = SkillStorageService(
        rootDirectoryProvider: () async => tempDir,
      );
      final installedDir = await storage.installedSkillsDirectory();
      final skillDir = Directory('${installedDir.path}/android-edge-skill');
      await skillDir.create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: Android Edge Skill
description: Improve Android edge-to-edge handling.
---
# Overview
Use Android edge-to-edge guidance.
''');

      final service = SkillIndexService(
        storageService: storage,
        frontmatterParser: const SkillFrontmatterParser(),
      );

      final result = await service.loadIndex();

      expect(result.descriptors, hasLength(1));
      expect(result.descriptors.single.id, 'android-edge-skill');
    });

    test('repo-local create artifact render analysis skill has valid frontmatter',
        () async {
      final skillFile = File(
        '.agents/skills/create-artifact-render-analysis/SKILL.md',
      );

      expect(await skillFile.exists(), isTrue);

      final parsed =
          const SkillFrontmatterParser().parse(await skillFile.readAsString());

      expect(parsed.name, 'create-artifact-render-analysis');
      expect(
        parsed.description,
        contains('create_artifact inline preview issues'),
      );
      expect(parsed.body, contains('scripts/analyze_create_artifact_render.sh'));
    });
  });
}
