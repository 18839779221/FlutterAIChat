import '../models/session/context_compaction_config.dart';
import '../models/session/model_budget_profile.dart';

/// Resolves model budget profiles from runtime overrides, built-ins, and fallback.
class ModelBudgetRegistry {
  ModelBudgetRegistry({
    Map<String, ModelBudgetProfile>? profiles,
    Map<String, ModelBudgetProfile>? familyProfiles,
    Map<String, ModelBudgetProfile>? runtimeOverrides,
    ModelBudgetProfile? fallbackProfile,
  })  : _profiles = Map.unmodifiable(profiles ?? _defaultProfiles),
        _familyProfiles = Map.unmodifiable(familyProfiles ?? _defaultFamilies),
        _runtimeOverrides = Map.unmodifiable(runtimeOverrides ?? const {}),
        _fallbackProfile = fallbackProfile ?? _defaultFallback;

  final Map<String, ModelBudgetProfile> _profiles;
  final Map<String, ModelBudgetProfile> _familyProfiles;
  final Map<String, ModelBudgetProfile> _runtimeOverrides;
  final ModelBudgetProfile _fallbackProfile;

  ModelBudgetProfile resolve(String modelName) {
    final normalized = _normalize(modelName);
    if (normalized.isEmpty) {
      return _fallbackProfile;
    }

    final runtime = _runtimeOverrides[normalized];
    if (runtime != null) {
      return runtime;
    }

    final exact = _profiles[normalized];
    if (exact != null) {
      return exact;
    }

    for (final entry in _runtimeOverrides.entries) {
      if (_matchesFamily(normalized, entry.key)) {
        return entry.value;
      }
    }
    for (final entry in _familyProfiles.entries) {
      if (_matchesFamily(normalized, entry.key)) {
        return entry.value;
      }
    }

    return _fallbackProfile;
  }

  static String _normalize(String modelName) => modelName.trim().toLowerCase();

  static bool _matchesFamily(String normalizedModel, String familyKey) {
    final normalizedFamily = _normalize(familyKey);
    if (normalizedFamily.isEmpty) {
      return false;
    }
    return normalizedModel == normalizedFamily ||
        normalizedModel.startsWith('$normalizedFamily-') ||
        normalizedModel.contains(normalizedFamily);
  }

  static const ModelBudgetProfile _defaultFallback = ModelBudgetProfile(
    modelId: 'fallback',
    maxContextTokens: 32000,
    reservedOutputTokens: 4000,
    reasoningReserveTokens: 4000,
    safetyMarginTokens: 2000,
    compactionConfig: ContextCompactionConfig(),
  );

  static const Map<String, ModelBudgetProfile> _defaultProfiles = {
    'gpt-5': ModelBudgetProfile(
      modelId: 'gpt-5',
      maxContextTokens: 128000,
      reservedOutputTokens: 12000,
      reasoningReserveTokens: 8000,
      safetyMarginTokens: 4000,
      compactionConfig: ContextCompactionConfig(),
    ),
    'gpt-4.1': ModelBudgetProfile(
      modelId: 'gpt-4.1',
      maxContextTokens: 128000,
      reservedOutputTokens: 12000,
      reasoningReserveTokens: 6000,
      safetyMarginTokens: 4000,
      compactionConfig: ContextCompactionConfig(),
    ),
  };

  static const Map<String, ModelBudgetProfile> _defaultFamilies = {
    'gpt': ModelBudgetProfile(
      modelId: 'gpt-family',
      maxContextTokens: 128000,
      reservedOutputTokens: 12000,
      reasoningReserveTokens: 8000,
      safetyMarginTokens: 4000,
      compactionConfig: ContextCompactionConfig(),
    ),
    'claude': ModelBudgetProfile(
      modelId: 'claude-family',
      maxContextTokens: 128000,
      reservedOutputTokens: 12000,
      reasoningReserveTokens: 8000,
      safetyMarginTokens: 4000,
      compactionConfig: ContextCompactionConfig(),
    ),
    'gemini': ModelBudgetProfile(
      modelId: 'gemini-family',
      maxContextTokens: 128000,
      reservedOutputTokens: 12000,
      reasoningReserveTokens: 8000,
      safetyMarginTokens: 4000,
      compactionConfig: ContextCompactionConfig(),
    ),
    'deepseek': ModelBudgetProfile(
      modelId: 'deepseek-family',
      maxContextTokens: 64000,
      reservedOutputTokens: 8000,
      reasoningReserveTokens: 8000,
      safetyMarginTokens: 4000,
      compactionConfig: ContextCompactionConfig(),
    ),
  };
}
