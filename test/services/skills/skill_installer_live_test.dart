import 'dart:io';

import 'package:ai_chat/services/skills/github_skill_fetcher.dart';
import 'package:ai_chat/services/skills/github_skill_source_resolver.dart';
import 'package:ai_chat/services/skills/skill_frontmatter_parser.dart';
import 'package:ai_chat/services/skills/skill_installer_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final liveEnabled = Platform.environment['RUN_LIVE_SKILL_TEST'] == '1';

  test(
    'installs android edge-to-edge skill from GitHub',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('skill-live-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final service = SkillInstallerService(
        storageService: SkillStorageService(
          rootDirectoryProvider: () async => tempDir,
        ),
        sourceResolver: const GitHubSkillSourceResolver(),
        fetcher: GitHubSkillFetcher(),
        frontmatterParser: const SkillFrontmatterParser(),
      );

      final preview = await service.previewFromGitHubUrl(
        'https://github.com/android/skills/tree/main/system/edge-to-edge',
      );
      expect(preview.name, isNotEmpty);
      expect(preview.description, isNotEmpty);

      final result = await service.installFromGitHubUrl(
        'https://github.com/android/skills/tree/main/system/edge-to-edge',
      );
      expect(result.skillId, isNotEmpty);
      expect(
        await File('${result.installedPath}/SKILL.md').exists(),
        isTrue,
      );
    },
    skip: liveEnabled ? false : 'Set RUN_LIVE_SKILL_TEST=1 to enable.',
  );
}
