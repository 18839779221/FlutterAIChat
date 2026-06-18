import 'package:ai_chat/bootstrap/app_bootstrap_state.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
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
  testWidgets('settings page renders grouped overview with current values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('模型与运行时'), findsOneWidget);
    expect(find.text('工具与安全'), findsOneWidget);
    expect(find.text('扩展能力'), findsOneWidget);
    expect(find.text('外观与兼容'), findsOneWidget);
    expect(find.text('当前 Provider'), findsOneWidget);
    expect(find.text('当前主题'), findsOneWidget);
    expect(find.text('进入管理'), findsNWidgets(4));
  });

  testWidgets('settings page keeps decorative hero copy removed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('Precision Settings'), findsNothing);
  });

  testWidgets(
      'settings page shows lightweight current values instead of inline management lists',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('当前 Model'), findsOneWidget);
    expect(find.text('当前生图模型'), findsOneWidget);
    expect(find.byKey(const Key('provider-switcher')), findsNothing);
    expect(find.text('自动执行白名单'), findsNothing);
    expect(find.text('这里可以安装到本地、启用或停用可用 skills。'), findsNothing);
  });

  testWidgets(
      'settings page supports lightweight theme and mode changes without navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'appearance.theme_id': 'claude',
      'tool.execution_mode': ToolExecutionMode.balanced.name,
    });
    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    await tester.tap(find.text('当前主题'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('theme-picker-sheet')), findsOneWidget);

    await tester.tap(find.text('Olive Paper'));
    await _settle(tester);

    expect(find.text('Olive Paper'), findsWidgets);

    await tester.tap(find.text('执行模式').first);
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('tool-execution-mode-picker-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('settings page removes inactive keyboard and cache toggles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();

    await _pumpSettingsPage(tester, repository: repository);

    expect(find.text('自动显示键盘'), findsNothing);
    expect(find.text('清除缓存'), findsNothing);
  });

  testWidgets('settings page waits for bootstrap ready before loading content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = await _buildRepository();
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        skillRuntimeServiceProvider.overrideWithValue(
          _FakeSkillRuntimeService(
            skills: const [
              SkillDescriptor(
                id: 'flutter-ui-design',
                name: 'Flutter UI Design',
                description: 'UI direction helper',
                bodyText: 'body',
                skillRootPath: '/skills/flutter-ui-design',
                entryFilePath: '/skills/flutter-ui-design/SKILL.md',
                sourceType: SkillSourceType.localInstalled,
                isEnabled: true,
              ),
            ],
          ),
        ),
      ],
    );
    container.read(appBootstrapStateNotifierProvider.notifier).update(
          const AppBootstrapState<Object?>.booting(),
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
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('模型与运行时'), findsNothing);
    expect(tester.takeException(), isNull);

    container.read(appBootstrapStateNotifierProvider.notifier).update(
          const AppBootstrapState<Object?>.ready(null),
        );
    await _settle(tester);

    expect(find.text('模型与运行时'), findsOneWidget);
    expect(find.text('工具与安全'), findsOneWidget);
  });
}

Future<AppSettingsRepository> _buildRepository() async {
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
          sideModelId: 'gpt-5-mini',
        ),
      ],
      additionalConfig: {
        'image_generation.default_provider_id': 'aigocode',
        'image_generation.default_model_id': 'gpt-5.4',
      },
    ),
  );
  await repository.saveAdditionalConfigValue(
    key: 'image_generation.default_provider_id',
    value: 'aigocode',
  );
  await repository.saveAdditionalConfigValue(
    key: 'image_generation.default_model_id',
    value: 'gpt-5.4',
  );
  await repository.setChatCompletionsAdapterType('sdk');
  return repository;
}

Future<void> _pumpSettingsPage(
  WidgetTester tester, {
  required AppSettingsRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        skillRuntimeServiceProvider.overrideWithValue(
          _FakeSkillRuntimeService(
            skills: const [
              SkillDescriptor(
                id: 'flutter-ui-design',
                name: 'Flutter UI Design',
                description: 'UI direction helper',
                bodyText: 'body',
                skillRootPath: '/skills/flutter-ui-design',
                entryFilePath: '/skills/flutter-ui-design/SKILL.md',
                sourceType: SkillSourceType.localInstalled,
                isEnabled: true,
              ),
              SkillDescriptor(
                id: 'playwright',
                name: 'Playwright',
                description: 'Browser automation',
                bodyText: 'body',
                skillRootPath: '/skills/playwright',
                entryFilePath: '/skills/playwright/SKILL.md',
                sourceType: SkillSourceType.githubInstalled,
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
  await _settle(tester);
  // Ignore any remaining scheduled frames from theme restoration or overlay
  // animation; assertions below target visible steady-state content.
  tester.binding.scheduleWarmUpFrame();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _FakeSkillRuntimeService extends SkillRuntimeService {
  _FakeSkillRuntimeService({required this.skills})
      : super(
          storageService: SkillStorageService(
            rootDirectoryProvider: () async =>
                throw UnimplementedError('not used in test'),
          ),
        );

  final List<SkillDescriptor> skills;

  @override
  Future<List<SkillDescriptor>> listInstalledSkills() async => skills;
}
