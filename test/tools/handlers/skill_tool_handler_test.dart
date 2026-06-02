import 'dart:io';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/skill/duplicate_skill_invocation_mode.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/skills/skill_context_formatter.dart';
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
      handler = SkillToolHandler(
        skillRuntimeService: runtimeService,
        settingsRepository: settingsRepository,
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

    test('execution context exposes current turn events to skill handlers', () {
      final context = ToolExecutionContext(
        groupId: 1,
        toolName: 'skill',
        arguments: const {'skill': 'edge-to-edge'},
        history: const <ChatMessage>[],
        now: DateTime(2026, 5, 15),
        currentTurnEvents: [
          ChatEvent(
            turnId: 10,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            payloadJson: const {
              'toolName': 'skill',
              'status': 'success',
              'data': {'skillId': 'edge-to-edge'},
            },
          ),
        ],
      );

      expect(context.currentTurnEvents, hasLength(1));
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
      expect(result.data['baseDirectory'], '/skills/installed/edge-to-edge');
      expect(result.data['instructionBody'], contains('# Workflow'));
    });

    test('execute reuses duplicate skill invocation in the same turn by default',
        () async {
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'skill',
          arguments: const {'skill': 'edge-to-edge'},
          history: const <ChatMessage>[],
          currentTurnEvents: [
            ChatEvent(
              turnId: 10,
              groupId: 1,
              sequence: 1,
              eventType: ChatEventType.toolResult,
              role: MessageRole.system,
              payloadJson: const {
                'toolName': 'skill',
                'status': 'success',
                'data': {
                  'skillId': 'edge-to-edge',
                  'name': 'edge-to-edge',
                },
              },
            ),
          ],
          now: DateTime(2026, 5, 9),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, 'Skill reused: edge-to-edge');
      expect(result.data['skillId'], 'edge-to-edge');
      expect(result.data['duplicateInvocation'], isTrue);
      expect(result.data['reloadPerformed'], isFalse);
      expect(result.errorMessage, isNull);
    });

    test('execute reloads duplicate skill invocation when mode is reload',
        () async {
      await settingsRepository.saveDuplicateSkillInvocationMode(
        DuplicateSkillInvocationMode.reload,
      );

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'skill',
          arguments: const {'skill': 'edge-to-edge'},
          history: const <ChatMessage>[],
          currentTurnEvents: [
            ChatEvent(
              turnId: 10,
              groupId: 1,
              sequence: 1,
              eventType: ChatEventType.toolResult,
              role: MessageRole.system,
              payloadJson: const {
                'toolName': 'skill',
                'status': 'success',
                'data': {
                  'skillId': 'edge-to-edge',
                  'name': 'edge-to-edge',
                },
              },
            ),
          ],
          now: DateTime(2026, 5, 9),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, 'Skill reloaded: edge-to-edge');
      expect(result.data['skillId'], 'edge-to-edge');
      expect(result.data['duplicateInvocation'], isTrue);
      expect(result.data['reloadPerformed'], isTrue);
    });

    test('execute resolves skill by declared skill name', () async {
      final installedRoot = await storageService.installedSkillsDirectory();
      final skillDir = Directory('${installedRoot.path}/verify-workflow');
      await skillDir.create(recursive: true);
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: Verify Workflow
description: Run project verification after code changes.
---
# Workflow
Run tests before claiming success.
''');

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'skill',
          arguments: const {'skill': 'Verify Workflow'},
          history: const <ChatMessage>[],
          now: DateTime(2026, 5, 9),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['skillId'], 'verify-workflow');
      expect(result.data['name'], 'Verify Workflow');
    });

    test(
        'execute returns truncated invoked skill payload when body exceeds budget',
        () async {
      final installedRoot = await storageService.installedSkillsDirectory();
      final skillDir = Directory('${installedRoot.path}/long-skill');
      await skillDir.create(recursive: true);
      final longBody = '${List.filled(120, 'A').join()}tail-sentinel';
      await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: long-skill
description: Has a long body.
---
$longBody
''');
      final truncatingHandler = SkillToolHandler(
        skillRuntimeService: runtimeService,
        skillContextFormatter: const SkillContextFormatter(
          maxInstructionCharacters: 80,
        ),
      );

      final result = await truncatingHandler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'skill',
          arguments: const {'skill': 'long-skill'},
          history: const <ChatMessage>[],
          now: DateTime(2026, 5, 9),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['instructionBodyTruncated'], isTrue);
      expect(
        result.data['originalInstructionLength'],
        greaterThan((result.data['instructionBody'] as String).length),
      );
      expect(result.data['instructionBody'], isNot(contains('tail-sentinel')));
    });
  });
}
