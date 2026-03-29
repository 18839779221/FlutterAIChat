import 'package:ai_chat/models/tool/tool_policy.dart';
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

  testWidgets('model config fields load repository defaults', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => const LlmLocalDefaults(
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        model: 'gpt-5.4',
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

    expect(find.widgetWithText(TextFormField, 'gpt-5.4'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'https://example.com/v1'),
      findsOneWidget,
    );
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
