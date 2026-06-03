import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/skill/duplicate_skill_invocation_mode.dart';
import 'package:ai_chat/models/skill/skill_descriptor.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/pages/settings_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings page removes decorative hero copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('Precision Settings'), findsNothing);
  });

  testWidgets('settings page shows model summary instead of inline pickers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('模型与连接'), findsOneWidget);
    expect(find.text('当前默认模型'), findsOneWidget);
    expect(find.text('进入模型配置'), findsOneWidget);
    expect(find.byKey(const Key('provider-switcher')), findsNothing);
    expect(find.text('当前提供方'), findsNothing);
    expect(find.text('当前模型'), findsNothing);
  });

  testWidgets('tool settings section still renders mode and whitelist entries',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'tool.execution_mode': ToolExecutionMode.balanced.name,
      'tool.trusted_names': ['fetch_webpage', 'create_reminder'],
    });
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('工具自动化'), findsOneWidget);
    expect(find.text('平衡'), findsOneWidget);
    expect(find.text('fetch_webpage'), findsOneWidget);
    expect(find.text('create_reminder'), findsOneWidget);
  });

  testWidgets('appearance section keeps theme choices without filler copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('界面偏好'), findsOneWidget);
    expect(find.text('当前主题'), findsOneWidget);
    expect(find.text('Claude'), findsAtLeastNWidgets(1));
    expect(find.text('Olive Paper'), findsOneWidget);
    expect(find.textContaining('主题作为一等公民管理'), findsNothing);
  });

  testWidgets('settings page removes inactive keyboard and cache toggles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('自动显示键盘'), findsNothing);
    expect(find.text('清除缓存'), findsNothing);
  });

  testWidgets('workspace picker updates current chat workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();
    final sessionCoordinator = _RecordingSessionCoordinator();
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        skillRuntimeServiceProvider
            .overrideWithValue(_EmptySkillRuntimeService()),
        chatSessionCoordinatorProvider
            .overrideWithValue(sessionCoordinator),
      ],
    );
    container.read(groupsProvider.notifier).setGroups([
      ChatGroup(
        id: 1,
        title: 'Default',
        lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
      ),
      ChatGroup(
        id: 2,
        title: 'Shared',
        workspaceId: 'ws_20260602_a3k9qx',
        lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
      ),
    ]);
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 1,
      title: 'Default',
      lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('workspace-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ws_20260602_a3k9qx').last);
    await tester.pumpAndSettle();

    expect(sessionCoordinator.updatedWorkspaceIds, ['ws_20260602_a3k9qx']);
  });
}

Future<AppSettingsRepository> _buildRepository() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettingsRepository(
    await SharedPreferences.getInstance(),
    localDefaultsLoader: () async => const LlmLocalDefaults(
      defaultProviderId: 'aigocode',
      defaultModelId: 'gpt-5.4',
      providers: [
        LlmProviderConfig(
          id: 'aigocode',
          name: 'AIGoCode',
          apiKey: 'test-key',
          baseUrl: 'https://example.com/v1',
          models: [
            LlmProviderModel(id: 'gpt-5.4', name: ''),
          ],
        ),
      ],
    ),
  );
}

Future<void> _pumpSettingsPage(
  WidgetTester tester, {
  required AppSettingsRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        skillRuntimeServiceProvider
            .overrideWithValue(_EmptySkillRuntimeService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _EmptySkillRuntimeService extends SkillRuntimeService {
  _EmptySkillRuntimeService()
      : super(
          storageService: SkillStorageService(
            rootDirectoryProvider: () async =>
                throw UnimplementedError('not used in test'),
          ),
        );

  @override
  Future<List<SkillDescriptor>> listInstalledSkills() async => const [];
}

class _RecordingSessionCoordinator extends ChatSessionCoordinator {
  final List<String?> updatedWorkspaceIds = [];

  @override
  Future<void> createNewGroup() async {}

  @override
  Future<void> deleteGroup(int id) async {}

  @override
  Future<void> loadCurrentGroup() async {}

  @override
  Future<void> loadGroups() async {}

  @override
  Future<void> loadMessages() async {}

  @override
  Future<void> loadMoreMessages() async {}

  @override
  Future<void> selectGroup(ChatGroup group) async {}

  @override
  Future<void> updateCurrentGroupWorkspace(String? workspaceId) async {
    updatedWorkspaceIds.add(workspaceId);
  }
}
