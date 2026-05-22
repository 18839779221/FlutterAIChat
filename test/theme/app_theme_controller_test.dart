import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/theme/app_theme_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to Claude theme and persists selected theme id', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(preferences);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appThemeControllerProvider).id, 'claude');

    await container.read(appThemeControllerProvider.notifier).setTheme('olive-paper');

    expect(await repository.getThemeId(), 'olive-paper');
    expect(container.read(appThemeControllerProvider).id, 'olive-paper');
  });
}
