import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/skill/installed_skill_record.dart';
import '../../models/skill/skill_descriptor.dart';
import 'skill_frontmatter_parser.dart';
import 'skill_storage_service.dart';

class SkillIndexResult {
  final List<SkillDescriptor> descriptors;
  final List<InstalledSkillRecord> invalidRecords;

  const SkillIndexResult({
    required this.descriptors,
    required this.invalidRecords,
  });
}

class SkillIndexService {
  SkillIndexService({
    required SkillStorageService storageService,
    SkillFrontmatterParser frontmatterParser = const SkillFrontmatterParser(),
  })  : _storageService = storageService,
        _frontmatterParser = frontmatterParser;

  final SkillStorageService _storageService;
  final SkillFrontmatterParser _frontmatterParser;

  Future<SkillIndexResult> loadIndex({
    Set<String>? enabledSkillIds,
  }) async {
    final installedDirectory = await _storageService.installedSkillsDirectory();
    if (!await installedDirectory.exists()) {
      return const SkillIndexResult(
        descriptors: [],
        invalidRecords: [],
      );
    }

    final descriptors = <SkillDescriptor>[];
    final invalidRecords = <InstalledSkillRecord>[];
    final children = installedDirectory
        .listSync()
        .whereType<Directory>()
        .toList(growable: false)
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final child in children) {
      final skillId = _normalizeSkillId(p.basename(child.path));
      final skillFile = File(p.join(child.path, 'SKILL.md'));
      if (!skillFile.existsSync()) {
        invalidRecords.add(
          InstalledSkillRecord(
            skillId: skillId,
            status: InstalledSkillStatus.invalid,
            installNotes: 'Missing SKILL.md.',
          ),
        );
        continue;
      }

      try {
        final parsed = _frontmatterParser.parse(await skillFile.readAsString());
        final isEnabled =
            enabledSkillIds == null ? true : enabledSkillIds.contains(skillId);
        descriptors.add(
          SkillDescriptor(
            id: skillId,
            name: parsed.name,
            description: parsed.description,
            bodyText: parsed.body,
            skillRootPath: _agentSkillRootPath(skillId),
            entryFilePath: _agentSkillEntryPath(skillId),
            sourceType: SkillSourceType.localInstalled,
            isEnabled: isEnabled,
          ),
        );
      } on SkillFrontmatterFormatException catch (error) {
        invalidRecords.add(
          InstalledSkillRecord(
            skillId: skillId,
            status: InstalledSkillStatus.invalid,
            installNotes: error.message,
          ),
        );
      }
    }

    return SkillIndexResult(
      descriptors: descriptors,
      invalidRecords: invalidRecords,
    );
  }

  String _normalizeSkillId(String value) {
    final lower = value.trim().toLowerCase();
    final normalized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  String _agentSkillRootPath(String skillId) {
    return '/skills/installed/$skillId';
  }

  String _agentSkillEntryPath(String skillId) {
    return '/skills/installed/$skillId/SKILL.md';
  }
}
