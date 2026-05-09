import 'dart:io';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/skill_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SkillToolHandler', () {
    late Directory tempDir;
    late SkillStorageService storageService;
    late AppSettingsRepository settingsRepository;
    late SkillRuntimeService runtimeService;
    late SkillToolHandler handler;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('skill-tool-handler-');
      storageService = SkillStorageService(
        rootDirectoryProvider: () async => tempDir,
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      settingsRepository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      );
      runtimeService = SkillRuntimeService(
        storageService: storageService,
        settingsRepository: settingsRepository,
      );
      handler = SkillToolHandler(skillRuntimeService: runtimeService);

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

    test('normalizeArguments rejects missing skill name', () async {
      final resolution = await handler.normalizeArguments(
        rawArguments: const {},
        userMessage: 'use the skill',
        history: const [],
        now: DateTime(2026, 5, 9),
      );

      expect(resolution.isValid, isFalse);
      expect(resolution.errorCode, 'invalid_skill');
    });

    test('execute fails when target skill is missing or disabled', () async {
      await settingsRepository.disableSkillId('edge-to-edge');

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'skill',
          arguments: const {'skill': 'edge-to-edge'},
          history: const <ChatMessage>[],
          now: DateTime(2026, 5, 9),
        ),
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'skill_not_available');
    });

    test('execute returns invoked skill payload for enabled skill', () async {
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'skill',
          arguments: const {'skill': 'edge-to-edge'},
          history: const <ChatMessage>[],
          now: DateTime(2026, 5, 9),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.toolName, 'skill');
      expect(result.data['skillId'], 'edge-to-edge');
      expect(result.data['name'], 'edge-to-edge');
      expect(result.data['baseDirectory'], contains('edge-to-edge'));
      expect(result.data['instructionBody'], contains('# Workflow'));
    });
  });
}
