import 'package:ai_chat/bootstrap/runtime_host_services.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('web host services avoid filesystem-backed runtime dependencies',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(preferences);

    final services = await buildRuntimeHostServices(
      isWeb: true,
      storage: _NoopChatStorage(),
      settingsRepository: settingsRepository,
    );

    expect(services.fileToolAdapters, isNull);
    expect(services.artifactFileStorageService, isNull);
    expect(services.chatAttachmentStorageService, isNull);
    expect(await services.skillRuntimeService.listInstalledSkills(), isEmpty);
    expect(
      await services.skillRuntimeService.listSkillCatalogEntries(),
      <SkillCatalogEntry>[],
    );
  });
}

class _NoopChatStorage implements ChatStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
