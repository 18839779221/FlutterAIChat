import 'dart:io';

import 'package:ai_chat/models/skill/github_skill_source.dart';
import 'package:ai_chat/services/skills/github_skill_source_resolver.dart';
import 'package:ai_chat/services/skills/skill_frontmatter_parser.dart';
import 'package:ai_chat/services/skills/skill_installer_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillInstallerService', () {
    setUp(() async {
      tempDirForTests =
          await Directory.systemTemp.createTemp('skill-installer-test-');
    });

    tearDown(() async {
      if (await tempDirForTests.exists()) {
        await tempDirForTests.delete(recursive: true);
      }
    });

    test('previews a valid GitHub skill source', () async {
      final service = _buildService(
        fetcher: _FakeSkillFetcher(const {
          'SKILL.md': '''
---
name: edge-to-edge
description: Improve Android edge-to-edge handling.
---
# Overview
Use Android edge-to-edge guidance.
''',
        }),
      );

      final preview = await service.previewFromGitHubUrl(
        'https://github.com/android/skills/tree/main/edge-to-edge',
      );

      expect(preview.name, 'edge-to-edge');
      expect(preview.description, 'Improve Android edge-to-edge handling.');
      expect(preview.source.owner, 'android');
      expect(preview.source.repo, 'skills');
    });

    test('installs a valid GitHub skill into local storage', () async {
      final service = _buildService(
        fetcher: _FakeSkillFetcher(const {
          'SKILL.md': '''
---
name: edge-to-edge
description: Improve Android edge-to-edge handling.
---
# Overview
Use Android edge-to-edge guidance.
''',
        }),
      );

      final result = await service.installFromGitHubUrl(
        'https://github.com/android/skills/tree/main/edge-to-edge',
      );

      expect(result.skillId, 'edge-to-edge');
      final installedDir = await service.storageService.skillDirectory('edge-to-edge');
      expect(await File('${installedDir.path}/SKILL.md').exists(), isTrue);
      expect(await File('${installedDir.path}/.skill-source.json').exists(), isTrue);
    });

    test('fails when the fetched source has no SKILL.md', () async {
      final service = _buildService(
        fetcher: _FakeSkillFetcher(const {
          'README.md': '# Nothing here',
        }),
      );

      expect(
        () => service.installFromGitHubUrl(
          'https://github.com/android/skills/tree/main/edge-to-edge',
        ),
        throwsA(isA<SkillInstallerException>()),
      );
    });
  });
}

SkillInstallerService _buildService({
  required _FakeSkillFetcher fetcher,
}) {
  final storage = SkillStorageService(
    rootDirectoryProvider: () async => tempDirForTests,
  );
  return SkillInstallerService(
    storageService: storage,
    sourceResolver: const GitHubSkillSourceResolver(),
    fetcher: fetcher,
    frontmatterParser: const SkillFrontmatterParser(),
  );
}

late Directory tempDirForTests;

class _FakeSkillFetcher implements SkillSourceFetcher {
  final Map<String, String> files;

  const _FakeSkillFetcher(this.files);

  @override
  Future<Map<String, String>> fetchSkillFiles(GitHubSkillSource source) async {
    return files;
  }
}
