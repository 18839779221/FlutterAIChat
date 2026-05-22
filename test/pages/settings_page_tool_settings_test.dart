import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/skill/duplicate_skill_invocation_mode.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/pages/settings_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/models/skill/skill_descriptor.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tool settings section renders mode and whitelist entries', (
    tester,
  ) async {
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

    expect(find.text('Precision Settings'), findsOneWidget);
    expect(find.text('工具自动化'), findsOneWidget);
    expect(find.text('平衡'), findsOneWidget);
    expect(find.text('fetch_webpage'), findsOneWidget);
    expect(find.text('create_reminder'), findsOneWidget);
    expect(find.text('将可信指令直接放行，降低重复确认。'), findsOneWidget);
  });

  testWidgets('appearance section renders built-in theme choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
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

    expect(find.text('界面偏好'), findsOneWidget);
    expect(find.text('当前主题'), findsOneWidget);
    expect(find.text('Claude'), findsAtLeastNWidgets(1));
    expect(find.text('Olive Paper'), findsOneWidget);
  });

  testWidgets('model access section renders compact provider and model pickers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
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
              LlmProviderModel(id: 'gpt-5-mini', name: ''),
            ],
          ),
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key-2',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o', name: ''),
            ],
          ),
        ],
      ),
    );

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

    expect(find.text('当前提供方'), findsOneWidget);
    expect(find.text('AIGoCode'), findsOneWidget);
    expect(find.text('当前模型'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);
    expect(find.text('https://example.com/v1'), findsOneWidget);
    expect(find.text('管理模型'), findsOneWidget);
  });

  testWidgets('switching provider updates available models and selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
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
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key-2',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o', name: ''),
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
        ],
      ),
    );

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

    await tester.tap(find.byTooltip('选择提供方'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(find.text('https://api.openai.com/v1'), findsOneWidget);
    expect(find.text('gpt-4o'), findsOneWidget);

    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();

    expect(find.text('gpt-4o').last, findsOneWidget);
    expect(find.text('gpt-4.1'), findsOneWidget);

    await tester.tap(find.text('gpt-4.1').last);
    await tester.pumpAndSettle();

    final selection = await repository.getSelectionState();
    expect(selection.selectedProviderId, 'openai');
    expect(selection.selectedModelId, 'gpt-4.1');
  });

  testWidgets('provider picker is disabled when current group is locked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
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
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key-2',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        skillRuntimeServiceProvider
            .overrideWithValue(_EmptySkillRuntimeService()),
      ],
    );
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 1,
      title: 'Locked',
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

    final providerButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('provider-switcher')),
    );
    expect(providerButton.onPressed, isNull);
    expect(find.text('当前会话已锁定 provider，新建会话方可切换'), findsOneWidget);
  });

  testWidgets('provider picker stays enabled for unsent draft group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
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
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'test-key-2',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(id: 'gpt-4o', name: ''),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        skillRuntimeServiceProvider
            .overrideWithValue(_EmptySkillRuntimeService()),
      ],
    );
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      title: 'Draft',
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

    final providerButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('provider-switcher')),
    );
    expect(providerButton.onPressed, isNotNull);
    expect(find.text('当前会话已锁定 provider，新建会话方可切换'), findsNothing);
  });

  testWidgets('model picker supports scrolling for long model lists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manyModels = List.generate(
      20,
      (index) => LlmProviderModel(id: 'model-$index', name: ''),
    );

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => LlmLocalDefaults(
        defaultProviderId: 'aigocode',
        defaultModelId: 'model-0',
        providers: [
          LlmProviderConfig(
            id: 'aigocode',
            name: 'AIGoCode',
            apiKey: 'test-key',
            baseUrl: 'https://example.com/v1',
            models: manyModels,
          ),
        ],
      ),
    );

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

    await tester.tap(find.byTooltip('选择模型'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('model-19'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('model-19'), findsOneWidget);
  });

  testWidgets('removing a trusted tool updates the repository-backed view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'tool.execution_mode': ToolExecutionMode.balanced.name,
      'tool.trusted_names': ['fetch_webpage'],
    });
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );

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

    final removeButton = find.byIcon(Icons.remove_circle_outline);
    await tester.scrollUntilVisible(
      removeButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(find.text('fetch_webpage'), findsNothing);
    expect(await repository.getTrustedToolNames(), isEmpty);
  });

  testWidgets('skills section renders installed skills', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          skillRuntimeServiceProvider.overrideWithValue(
            _StaticSkillRuntimeService(
              skills: const [
                SkillDescriptor(
                  id: 'edge-to-edge',
                  name: 'edge-to-edge',
                  description: 'Improve Android edge-to-edge handling.',
                  bodyText: '# Workflow\nPrefer Android edge-to-edge guidance.',
                  skillRootPath: '/tmp/skills/edge-to-edge',
                  entryFilePath: '/tmp/skills/edge-to-edge/SKILL.md',
                  sourceType: SkillSourceType.localInstalled,
                  isEnabled: true,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Skills'), findsOneWidget);
    expect(
      find.textContaining('运行时上下文'),
      findsOneWidget,
    );
    expect(find.text('edge-to-edge'), findsOneWidget);
    expect(find.text('Improve Android edge-to-edge handling.'), findsOneWidget);
    expect(find.text('重复调用时重载 Skill'), findsOneWidget);
    expect(find.text('关闭时重复调用直接复用已加载结果，不再向用户显示失败。'), findsOneWidget);
  });

  testWidgets('skills section toggles duplicate invocation reload mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          skillRuntimeServiceProvider.overrideWithValue(
            _StaticSkillRuntimeService(
              skills: const [
                SkillDescriptor(
                  id: 'edge-to-edge',
                  name: 'edge-to-edge',
                  description: 'Improve Android edge-to-edge handling.',
                  bodyText: '# Workflow\nPrefer Android edge-to-edge guidance.',
                  skillRootPath: '/tmp/skills/edge-to-edge',
                  entryFilePath: '/tmp/skills/edge-to-edge/SKILL.md',
                  sourceType: SkillSourceType.localInstalled,
                  isEnabled: true,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final reloadSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('重复调用时重载 Skill'),
        matching: find.byType(SettingsRow),
      ),
      matching: find.byType(Switch),
    );

    expect(
      await repository.getDuplicateSkillInvocationMode(),
      DuplicateSkillInvocationMode.reuse,
    );

    await tester.tap(reloadSwitch);
    await tester.pumpAndSettle();

    expect(
      await repository.getDuplicateSkillInvocationMode(),
      DuplicateSkillInvocationMode.reload,
    );
  });

  testWidgets('disabled skills remain visible in settings for re-enable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          skillRuntimeServiceProvider.overrideWithValue(
            _StaticSkillRuntimeService(
              installedSkills: const [
                SkillDescriptor(
                  id: 'edge-to-edge',
                  name: 'edge-to-edge',
                  description: 'Improve Android edge-to-edge handling.',
                  bodyText: '# Workflow\nPrefer Android edge-to-edge guidance.',
                  skillRootPath: '/tmp/skills/edge-to-edge',
                  entryFilePath: '/tmp/skills/edge-to-edge/SKILL.md',
                  sourceType: SkillSourceType.localInstalled,
                  isEnabled: false,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('edge-to-edge'), findsOneWidget);
    final disabledSwitch = tester.widget<Switch>(
      find.descendant(
        of: find.ancestor(
          of: find.text('edge-to-edge'),
          matching: find.byType(SettingsRow),
        ),
        matching: find.byType(Switch),
      ),
    );
    expect(disabledSwitch.value, isFalse);
  });
}

class _EmptySkillRuntimeService extends SkillRuntimeService {
  _EmptySkillRuntimeService()
      : super(
          storageService: SkillStorageService(
            rootDirectoryProvider: () async =>
                throw UnimplementedError('not used in this test'),
          ),
        );

  @override
  Future<List<SkillDescriptor>> listAvailableSkills() async => const [];

  @override
  Future<List<SkillDescriptor>> listInstalledSkills() async => const [];
}

class _StaticSkillRuntimeService extends SkillRuntimeService {
  _StaticSkillRuntimeService({
    List<SkillDescriptor>? skills,
    List<SkillDescriptor>? installedSkills,
  })  : skills = skills ?? installedSkills ?? const [],
        installedSkills = installedSkills ?? skills ?? const [],
        super(
          storageService: SkillStorageService(
            rootDirectoryProvider: () async =>
                throw UnimplementedError('not used in this test'),
          ),
        );

  final List<SkillDescriptor> skills;
  final List<SkillDescriptor> installedSkills;

  @override
  Future<List<SkillDescriptor>> listAvailableSkills() async => skills;

  @override
  Future<List<SkillDescriptor>> listInstalledSkills() async => installedSkills;
}
