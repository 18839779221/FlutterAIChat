import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/llm/llm_selection_state.dart';
import 'package:ai_chat/pages/model_management_page.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/llm_model_discovery_service.dart';
import 'package:ai_chat/services/llm_model_test_service.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/immersive_settings_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('model management page uses immersive nested header', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModelManagementPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-floating-header')),
      findsOneWidget,
    );
    expect(find.text('模型配置'), findsOneWidget);
    expect(find.byKey(settingsFloatingHeaderSurfaceKey), findsNothing);
  });

  testWidgets(
      'model management renders provider-first list with management sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );
    await repository.saveProvider(
      const LlmProviderConfig(
        id: 'aigocode',
        name: 'AIGoCode',
        apiKey: 'key',
        baseUrl: 'https://api.aigocode.com/v1',
        models: [
          LlmProviderModel(id: 'gpt-5.4', name: ''),
          LlmProviderModel(id: 'gpt-5-mini', name: ''),
        ],
      ),
    );
    await repository.saveSelectionState(
      const LlmSelectionState(
        selectedProviderId: 'aigocode',
        selectedModelId: 'gpt-5.4',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModelManagementPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前接入'), findsOneWidget);
    expect(find.text('Provider 列表'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);
    expect(find.text('新增 Provider'), findsOneWidget);
    expect(find.text('AIGoCode'), findsWidgets);
    expect(find.text('2 个模型'), findsOneWidget);
    expect(find.text('编辑'), findsWidgets);
    expect(find.text('删除'), findsWidgets);
    expect(find.text('当前选中模型'), findsNothing);
    expect(find.text('用于当前会话'), findsNothing);
  });

  testWidgets('model management removes overview hero copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );
    await repository.saveProvider(
      const LlmProviderConfig(
        id: 'aigocode',
        name: 'AIGoCode',
        apiKey: 'key',
        baseUrl: 'https://api.aigocode.com/v1',
        models: [
          LlmProviderModel(id: 'gpt-5.4', name: ''),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModelManagementPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前会话候选'), findsNothing);
    expect(find.text('准备接入'), findsNothing);
  });

  testWidgets('provider detail promotes discover models and fallback manual add',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );
    await repository.saveProvider(
      const LlmProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        apiKey: 'key',
        baseUrl: 'https://api.openai.com/v1',
        models: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModelManagementPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('编辑').first);
    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();

    expect(find.text('探测模型'), findsOneWidget);
    expect(find.text('手动新增模型'), findsOneWidget);
    expect(find.text('Provider 名称'), findsOneWidget);
    expect(find.text('模型目录'), findsOneWidget);
    expect(find.text('用于当前会话'), findsNothing);
  });

  testWidgets('discovered models are persisted and can become current session selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => null,
    );
    await repository.saveProvider(
      const LlmProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        apiKey: 'key',
        baseUrl: 'https://api.openai.com/v1',
        models: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModelManagementPage(
          repository: repository,
          discoveryService: _FakeDiscoveryService(
            models: const [
              LlmProviderModel(id: 'gpt-4o-mini', name: ''),
              LlmProviderModel(id: 'gpt-4.1', name: ''),
            ],
          ),
          testService: _FakeModelTestService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('编辑').first);
    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('探测模型'));
    await tester.tap(find.text('探测模型'));
    await tester.pumpAndSettle();

    expect(find.text('gpt-4o-mini'), findsWidgets);
    expect(find.text('gpt-4.1'), findsWidgets);

    await tester.ensureVisible(find.text('用于当前会话').first);
    await tester.tap(find.text('用于当前会话').first);
    await tester.pumpAndSettle();

    final providers = await repository.getProviders();
    final selection = await repository.getSelectionState();
    expect(providers.single.models, hasLength(2));
    expect(selection.selectedModelId, 'gpt-4o-mini');
  });
}

class _FakeDiscoveryService extends LlmModelDiscoveryService {
  _FakeDiscoveryService({required this.models});

  final List<LlmProviderModel> models;

  @override
  Future<List<LlmProviderModel>> discoverModels({
    required LlmProviderConfig provider,
  }) async {
    return models;
  }
}

class _FakeModelTestService extends LlmModelTestService {
  @override
  Future<String> testModel({
    required LlmProviderConfig provider,
    required LlmProviderModel model,
  }) async {
    return 'pong';
  }
}
