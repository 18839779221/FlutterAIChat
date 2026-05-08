import 'dart:io';

import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SkillRuntimeService', () {
    late Directory tempDir;
    late SkillStorageService storageService;
    late AppSettingsRepository settingsRepository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('skill-runtime-test-');
      storageService = SkillStorageService(
        rootDirectoryProvider: () async => tempDir,
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      settingsRepository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      );

      final installedRoot = await storageService.installedSkillsDirectory();
      final skillDir = Directory('${installedRoot.path}/edge-to-edge');
      await skillDir.create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: edge-to-edge
description: Improve Android edge-to-edge handling.
---
# Workflow
Prefer Android edge-to-edge guidance for this task.
''');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('does not expose disabled skill in catalog list', () async {
      await settingsRepository.disableSkillId('edge-to-edge');
      final service = SkillRuntimeService(
        storageService: storageService,
        settingsRepository: settingsRepository,
      );

      final catalog = await service.listSkillCatalogEntries();

      expect(catalog, isEmpty);
    });

    test('lists enabled skills as lightweight catalog entries', () async {
      final service = SkillRuntimeService(
        storageService: storageService,
        settingsRepository: settingsRepository,
      );

      final catalog = await service.listSkillCatalogEntries();

      expect(catalog, hasLength(1));
      expect(catalog.single.id, 'edge-to-edge');
      expect(catalog.single.name, 'edge-to-edge');
      expect(catalog.single.description, contains('Improve Android edge-to-edge'));
    });

    test('reads full skill descriptor from filesystem by skill id', () async {
      final service = SkillRuntimeService(
        storageService: storageService,
        settingsRepository: settingsRepository,
      );

      final descriptor = await service.loadSkillById('edge-to-edge');

      expect(descriptor, isNotNull);
      expect(descriptor!.bodyText, contains('# Workflow'));
      expect(descriptor.entryFilePath, contains('SKILL.md'));
    });
  });
}
