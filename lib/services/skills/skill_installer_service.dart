import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/skill/github_skill_source.dart';
import 'github_skill_source_resolver.dart';
import 'skill_frontmatter_parser.dart';
import 'skill_storage_service.dart';

abstract class SkillSourceFetcher {
  Future<Map<String, String>> fetchSkillFiles(GitHubSkillSource source);
}

class SkillInstallPreview {
  final GitHubSkillSource source;
  final String name;
  final String description;

  const SkillInstallPreview({
    required this.source,
    required this.name,
    required this.description,
  });
}

class SkillInstallResult {
  final String skillId;
  final String installedPath;

  const SkillInstallResult({
    required this.skillId,
    required this.installedPath,
  });
}

class SkillInstallerException implements Exception {
  final String message;

  const SkillInstallerException(this.message);

  @override
  String toString() => 'SkillInstallerException: $message';
}

class SkillInstallerService {
  SkillInstallerService({
    required SkillStorageService storageService,
    required GitHubSkillSourceResolver sourceResolver,
    required SkillSourceFetcher fetcher,
    SkillFrontmatterParser frontmatterParser = const SkillFrontmatterParser(),
  })  : _storageService = storageService,
        _sourceResolver = sourceResolver,
        _fetcher = fetcher,
        _frontmatterParser = frontmatterParser;

  final SkillStorageService _storageService;
  final GitHubSkillSourceResolver _sourceResolver;
  final SkillSourceFetcher _fetcher;
  final SkillFrontmatterParser _frontmatterParser;

  SkillStorageService get storageService => _storageService;

  Future<SkillInstallPreview> previewFromGitHubUrl(String input) async {
    final source = _sourceResolver.resolve(input);
    final files = await _fetcher.fetchSkillFiles(source);
    final skillContent = files['SKILL.md'];
    if (skillContent == null) {
      throw const SkillInstallerException('Missing SKILL.md.');
    }
    final parsed = _frontmatterParser.parse(skillContent);
    return SkillInstallPreview(
      source: source,
      name: parsed.name,
      description: parsed.description,
    );
  }

  Future<SkillInstallResult> installFromGitHubUrl(String input) async {
    final preview = await previewFromGitHubUrl(input);
    final skillId = _normalizeSkillId(preview.name);
    final skillDir = await _storageService.skillDirectory(skillId);
    if (!await skillDir.exists()) {
      await skillDir.create(recursive: true);
    }

    final source = preview.source;
    final files = await _fetcher.fetchSkillFiles(source);
    for (final entry in files.entries) {
      final target = File(p.join(skillDir.path, entry.key));
      await target.parent.create(recursive: true);
      await target.writeAsString(entry.value);
    }

    final sourceFile = File(p.join(skillDir.path, '.skill-source.json'));
    await sourceFile.writeAsString(
      jsonEncode({
        'owner': source.owner,
        'repo': source.repo,
        'ref': source.ref,
        'subdirectory': source.subdirectory,
        'sourceUrl': input,
      }),
    );

    return SkillInstallResult(
      skillId: skillId,
      installedPath: skillDir.path,
    );
  }

  String _normalizeSkillId(String value) {
    final lower = value.trim().toLowerCase();
    final normalized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }
}
