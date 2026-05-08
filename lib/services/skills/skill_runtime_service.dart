import '../../models/skill/skill_catalog_entry.dart';
import '../../models/skill/skill_descriptor.dart';
import '../../repositories/app_settings_repository.dart';
import 'skill_index_service.dart';
import 'skill_storage_service.dart';

class SkillRuntimeService {
  SkillRuntimeService({
    required SkillStorageService storageService,
    AppSettingsRepository? settingsRepository,
    SkillIndexService? indexService,
  })  : _indexService = indexService ?? SkillIndexService(storageService: storageService),
        _settingsRepository = settingsRepository;

  final SkillIndexService _indexService;
  final AppSettingsRepository? _settingsRepository;

  Future<List<SkillDescriptor>> listAvailableSkills() async {
    final index = await _loadEnabledIndex();
    return index.descriptors.where((skill) => skill.isEnabled).toList(growable: false);
  }

  Future<List<SkillCatalogEntry>> listSkillCatalogEntries() async {
    final skills = await listAvailableSkills();
    return skills
        .map(
          (skill) => SkillCatalogEntry(
            id: skill.id,
            name: skill.name,
            description: skill.description,
            qualifiedPath: skill.skillRootPath,
            isEnabled: skill.isEnabled,
          ),
        )
        .toList(growable: false);
  }

  Future<SkillDescriptor?> loadSkillById(String skillId) async {
    final normalized = skillId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final skills = await listAvailableSkills();
    for (final skill in skills) {
      if (skill.id == normalized) {
        return skill;
      }
    }
    return null;
  }

  Future<Set<String>> _loadDisabledSkillIds() async {
    final repository = _settingsRepository;
    if (repository == null) {
      return const <String>{};
    }
    return repository.getDisabledSkillIds();
  }

  Future<Set<String>> _resolveEnabledSkillIds(Set<String> disabledSkillIds) async {
    final rawIndex = await _indexService.loadIndex();
    return rawIndex.descriptors
        .map((skill) => skill.id)
        .where((id) => !disabledSkillIds.contains(id))
        .toSet();
  }

  Future<SkillIndexResult> _loadEnabledIndex() async {
    final disabledSkillIds = await _loadDisabledSkillIds();
    final enabledSkillIds = await _resolveEnabledSkillIds(disabledSkillIds);
    return _indexService.loadIndex(enabledSkillIds: enabledSkillIds);
  }
}
