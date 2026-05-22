import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme_spec.dart';

final appThemeControllerProvider =
    NotifierProvider<AppThemeController, AppThemeSpec>(AppThemeController.new);

class AppThemeController extends Notifier<AppThemeSpec> {
  AppSettingsRepository get _repository => ref.read(appSettingsRepositoryProvider);

  @override
  AppThemeSpec build() {
    _restorePersistedTheme();
    return AppThemeSpec.claude();
  }

  Future<void> _restorePersistedTheme() async {
    final storedId = await _repository.getThemeId();
    if (storedId == null) {
      return;
    }
    final resolved = AppThemeSpec.resolveById(storedId);
    if (resolved == null) {
      return;
    }
    state = resolved;
  }

  Future<void> setTheme(String id) async {
    final nextTheme = AppThemeSpec.resolveById(id);
    if (nextTheme == null) {
      return;
    }
    state = nextTheme;
    await _repository.saveThemeId(nextTheme.id);
  }
}
