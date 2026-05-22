import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/models/skill/duplicate_skill_invocation_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppSettingsRepository skills', () {
    late AppSettingsRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      );
    });

    test('returns empty disabled skills by default', () async {
      expect(await repository.getDisabledSkillIds(), isEmpty);
    });

    test('disables and re-enables a skill id', () async {
      await repository.disableSkillId('edge-to-edge');
      expect(await repository.getDisabledSkillIds(), {'edge-to-edge'});

      await repository.enableSkillId('edge-to-edge');
      expect(await repository.getDisabledSkillIds(), isEmpty);
    });

    test('stores the latest skill install url', () async {
      await repository.saveLatestSkillInstallUrl(
        'https://github.com/android/skills/tree/main/edge-to-edge',
      );

      expect(
        await repository.getLatestSkillInstallUrl(),
        'https://github.com/android/skills/tree/main/edge-to-edge',
      );
    });

    test('defaults duplicate skill invocation mode to reuse without reload',
        () async {
      expect(
        await repository.getDuplicateSkillInvocationMode(),
        DuplicateSkillInvocationMode.reuse,
      );
    });

    test('persists duplicate skill invocation mode', () async {
      await repository.saveDuplicateSkillInvocationMode(
        DuplicateSkillInvocationMode.reload,
      );

      expect(
        await repository.getDuplicateSkillInvocationMode(),
        DuplicateSkillInvocationMode.reload,
      );
    });
  });
}
