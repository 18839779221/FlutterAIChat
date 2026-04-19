import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/llm/llm_selection_state.dart';
import 'package:ai_chat/pages/model_management_page.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders providers and can switch current model', (tester) async {
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
        baseUrl: 'https://api.aigocode.com',
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
        defaultProviderId: 'aigocode',
        defaultModelId: 'gpt-5.4',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModelManagementPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AIGoCode'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsWidgets);
    expect(find.text('gpt-5-mini'), findsWidgets);
    expect(find.text('当前使用'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '使用此模型').last);
    await tester.pumpAndSettle();

    final selection = await repository.getSelectionState();
    expect(selection.selectedModelId, 'gpt-5-mini');
  });

  testWidgets('can open add provider form from management page', (tester) async {
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

    await tester.tap(find.byTooltip('新增提供方'));
    await tester.pumpAndSettle();

    expect(find.text('新增提供方'), findsOneWidget);
    expect(find.text('提供方名称'), findsOneWidget);
    expect(find.text('模型列表'), findsOneWidget);
  });
}
