import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_access_snapshot.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ToolPolicyService', () {
    late AppSettingsRepository repository;
    late ToolPolicyService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      );
      service = ToolPolicyService(repository: repository);
    });

    test('balanced mode auto-runs read-only tools', () async {
      const searchTool = ToolDefinition(
        name: 'search_chat_history',
        title: '搜索聊天记录',
        parameters: {'query': 'string'},
      );
      const fetchTool = ToolDefinition(
        name: 'fetch_webpage',
        title: '读取网页',
        parameters: {'url': 'string'},
      );

      expect(
        await service.resolveExecutionMode(searchTool),
        ToolPolicyDecision.autoRun,
      );
      expect(
        await service.resolveExecutionMode(fetchTool),
        ToolPolicyDecision.autoRun,
      );
    });

    test('balanced mode requires confirmation for side-effect tools', () async {
      const reminderTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      expect(
        await service.resolveExecutionMode(reminderTool),
        ToolPolicyDecision.requireConfirmation,
      );
    });

    test('trusting a tool promotes it to auto-run', () async {
      const reminderTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      await service.trustTool(reminderTool.name);

      expect(
        await service.resolveExecutionMode(reminderTool),
        ToolPolicyDecision.autoRun,
      );
      expect(
          await repository.getTrustedToolNames(), contains(reminderTool.name));
    });

    test('untrusting a tool restores confirmation behavior', () async {
      const reminderTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      await service.trustTool(reminderTool.name);
      await service.untrustTool(reminderTool.name);

      expect(
        await service.resolveExecutionMode(reminderTool),
        ToolPolicyDecision.requireConfirmation,
      );
      expect(await repository.getTrustedToolNames(),
          isNot(contains(reminderTool.name)));
    });

    test('blocking a tool returns blocked policy decision', () async {
      const reminderTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      await service.blockTool(reminderTool.name);

      expect(
        await service.resolveExecutionMode(reminderTool),
        ToolPolicyDecision.blocked,
      );
      expect(
        await repository.getBlockedToolNames(),
        contains(reminderTool.name),
      );
    });

    test('resolveToolAccess returns shared planner and runtime policy snapshot',
        () async {
      const reminderTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      final confirmationAccess = await service.resolveToolAccess(reminderTool);
      expect(
        confirmationAccess.executionDecision,
        ToolPolicyDecision.requireConfirmation,
      );
      expect(confirmationAccess.executionPolicyLabel, 'require_confirmation');
      expect(confirmationAccess.isVisibleToPlanner, isTrue);

      await service.blockTool(reminderTool.name);

      final blockedAccess = await service.resolveToolAccess(reminderTool);
      expect(blockedAccess.executionDecision, ToolPolicyDecision.blocked);
      expect(blockedAccess.executionPolicyLabel, 'blocked');
      expect(blockedAccess.isVisibleToPlanner, isFalse);
    });

    test(
        'tool policy outputs stable blocked/require_confirmation/auto_run labels',
        () async {
      const readTool = ToolDefinition(
        name: 'search_chat_history',
        title: '搜索聊天记录',
        parameters: {'query': 'string'},
      );
      const riskyTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      final autoRunAccess = await service.resolveToolAccess(readTool);
      final confirmationAccess = await service.resolveToolAccess(riskyTool);
      await service.blockTool(riskyTool.name);
      final blockedAccess = await service.resolveToolAccess(riskyTool);

      expect(autoRunAccess.executionPolicyLabel, 'auto_run');
      expect(autoRunAccess.executionDecision, ToolPolicyDecision.autoRun);

      expect(
        confirmationAccess.executionPolicyLabel,
        'require_confirmation',
      );
      expect(
        confirmationAccess.executionDecision,
        ToolPolicyDecision.requireConfirmation,
      );

      expect(blockedAccess.executionPolicyLabel, 'blocked');
      expect(blockedAccess.executionDecision, ToolPolicyDecision.blocked);
    });

    test(
        'tool policy planner visibility stays consistent with execution policy',
        () async {
      const readTool = ToolDefinition(
        name: 'search_chat_history',
        title: '搜索聊天记录',
        parameters: {'query': 'string'},
      );
      const riskyTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
      );

      final visibleAccess = <ToolAccessSnapshot>[
        await service.resolveToolAccess(readTool),
        await service.resolveToolAccess(riskyTool),
      ];
      for (final access in visibleAccess) {
        expect(access.isVisibleToPlanner, isTrue);
        expect(
          access.executionDecision,
          isNot(ToolPolicyDecision.blocked),
        );
        expect(access.executionPolicyLabel, isNot('blocked'));
      }

      await service.blockTool(riskyTool.name);
      final blockedAccess = await service.resolveToolAccess(riskyTool);
      expect(blockedAccess.isVisibleToPlanner, isFalse);
      expect(blockedAccess.executionDecision, ToolPolicyDecision.blocked);
      expect(blockedAccess.executionPolicyLabel, 'blocked');
    });

    test('generate_image is hidden from planner without image capable model',
        () async {
      const generateImageTool = ToolDefinition(
        name: 'generate_image',
        title: '生成图片',
        parameters: {'prompt': 'string'},
      );

      final access = await service.resolveToolAccess(generateImageTool);

      expect(access.executionDecision, ToolPolicyDecision.blocked);
      expect(access.isVisibleToPlanner, isFalse);
      expect(access.executionPolicyLabel, 'blocked');
    });

    test('generate_image is visible when an image capable model exists',
        () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repositoryWithImageModel = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          providers: [
            LlmProviderConfig(
              id: 'beehears',
              name: 'Beehears',
              apiKey: 'image-key',
              baseUrl: 'https://ai.beehears.com/v1',
              models: [
                LlmProviderModel(
                  id: 'gpt-image-2',
                  name: 'GPT Image 2',
                  supportsImageGeneration: true,
                ),
              ],
            ),
          ],
        ),
      );
      final serviceWithImageModel = ToolPolicyService(
        repository: repositoryWithImageModel,
      );
      const generateImageTool = ToolDefinition(
        name: 'generate_image',
        title: '生成图片',
        parameters: {'prompt': 'string'},
      );

      final access =
          await serviceWithImageModel.resolveToolAccess(generateImageTool);

      expect(access.executionDecision, ToolPolicyDecision.autoRun);
      expect(access.isVisibleToPlanner, isTrue);
    });
  });
}
