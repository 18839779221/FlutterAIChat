import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/pages/settings_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/theme/app_theme.dart';
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

  testWidgets('model access section renders compact provider and model pickers', (tester) async {
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
}
