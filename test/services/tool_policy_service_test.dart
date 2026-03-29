import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
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
        description: '搜索历史消息',
        parameters: {'query': 'string'},
      );
      const fetchTool = ToolDefinition(
        name: 'fetch_webpage',
        title: '读取网页',
        description: '读取网页正文',
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
        description: '创建系统提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
        riskLevel: 'medium',
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
        description: '创建系统提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
        riskLevel: 'medium',
      );

      await service.trustTool(reminderTool.name);

      expect(
        await service.resolveExecutionMode(reminderTool),
        ToolPolicyDecision.autoRun,
      );
      expect(await repository.getTrustedToolNames(), contains(reminderTool.name));
    });

    test('untrusting a tool restores confirmation behavior', () async {
      const reminderTool = ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        description: '创建系统提醒',
        parameters: {'title': 'string'},
        requiresConfirmation: true,
        riskLevel: 'medium',
      );

      await service.trustTool(reminderTool.name);
      await service.untrustTool(reminderTool.name);

      expect(
        await service.resolveExecutionMode(reminderTool),
        ToolPolicyDecision.requireConfirmation,
      );
      expect(await repository.getTrustedToolNames(), isNot(contains(reminderTool.name)));
    });
  });
}
