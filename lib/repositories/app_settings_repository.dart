import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm/llm_config.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/llm/llm_selection_state.dart';
import '../models/skill/duplicate_skill_invocation_mode.dart';
import '../models/speech/speech_input_config.dart';
import 'llm_local_defaults.dart';

class AppSettingsRepository {
  static const String _providersJsonKey = 'llm.providers_json';
  static const String _selectionJsonKey = 'llm.selection_json';
  static const String _providersSeededKey = 'llm.providers_seeded';
  static const String _toolExecutionModeKey = 'tool.execution_mode';
  static const String _trustedToolNamesKey = 'tool.trusted_names';
  static const String _blockedToolNamesKey = 'tool.blocked_names';
  static const String _disabledSkillIdsKey = 'skills.disabled_ids';
  static const String _latestSkillInstallUrlKey = 'skills.latest_install_url';
  static const String _chatCompletionsAdapterKey = 'llm.chat_completions_adapter';
  static const String _duplicateSkillInvocationModeKey =
      'skills.duplicate_invocation_mode';
  static const String _themeIdKey = 'appearance.theme_id';
  static const String _runtimeImageInputSupportKey =
      'llm.runtime_image_input_support_json';
  static const String _legacyApiKeyKey = 'llm.api_key';
  static const String _legacyBaseUrlKey = 'llm.base_url';
  static const String _legacyModelKey = 'llm.model';
  static const String _defaultProviderId = 'default-provider';
  static const String _defaultModelName = 'default-model';

  final SharedPreferences _preferences;
  final Future<LlmLocalDefaults?> Function()? _localDefaultsLoader;
  Future<LlmLocalDefaults?>? _cachedLocalDefaults;

  AppSettingsRepository(
    this._preferences, {
    Future<LlmLocalDefaults?> Function()? localDefaultsLoader,
  }) : _localDefaultsLoader =
            localDefaultsLoader ?? const AssetLlmLocalDefaultsLoader().load;

  Future<LlmLocalDefaults?> _getLocalDefaults() {
    return _cachedLocalDefaults ??=
        _localDefaultsLoader?.call() ?? Future.value(null);
  }

  Future<void> ensureSeededProviders() async {
    if (_preferences.getBool(_providersSeededKey) == true &&
        _readProvidersFromPreferences().isNotEmpty) {
      return;
    }

    final defaults = await _getLocalDefaults();
    if (defaults == null || defaults.providers.isEmpty) {
      return;
    }

    await _writeProviders(defaults.providers);
    final defaultProvider = defaults.providers.first;
    final seededDefaultModelId = defaults.defaultModelId ??
        (defaultProvider.models.isEmpty ? null : defaultProvider.models.first.id);
    await _writeSelection(
      LlmSelectionState(
        selectedProviderId: defaults.defaultProviderId ?? defaultProvider.id,
        selectedModelId: seededDefaultModelId,
        defaultProviderId: defaults.defaultProviderId ?? defaultProvider.id,
        defaultModelId: seededDefaultModelId,
      ),
    );
    await _preferences.setBool(_providersSeededKey, true);
  }

  Future<List<LlmProviderConfig>> getProviders() async {
    await ensureSeededProviders();
    return _readProvidersFromPreferences();
  }

  List<LlmProviderConfig> _readProvidersFromPreferences() {
    final raw = _preferences.getString(_providersJsonKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((item) => LlmProviderConfig.fromJson(Map<String, dynamic>.from(item)))
        .where(
          (item) =>
              item.id.isNotEmpty &&
              item.name.isNotEmpty &&
              item.baseUrl.isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<LlmProviderConfig?> getProviderById(String providerId) async {
    final providers = await getProviders();
    for (final provider in providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }
    return null;
  }

  Future<void> saveProvider(LlmProviderConfig provider) async {
    final providers = [...await getProviders()];
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index >= 0) {
      providers[index] = provider;
    } else {
      providers.add(provider);
    }

    await _writeProviders(providers);

    final selection = await _normalizeSelection(
      await getSelectionState(),
      providers: providers,
    );
    await _writeSelection(selection);
  }

  Future<void> deleteProvider(String providerId) async {
    final providers = (await getProviders())
        .where((item) => item.id != providerId)
        .toList(growable: false);
    await _writeProviders(providers);
    final selection = await _normalizeSelection(
      await getSelectionState(),
      providers: providers,
    );
    await _writeSelection(selection);
  }

  Future<LlmSelectionState> getSelectionState() async {
    await ensureSeededProviders();
    final raw = _preferences.getString(_selectionJsonKey);
    if (raw == null || raw.trim().isEmpty) {
      final normalized = await _normalizeSelection(const LlmSelectionState());
      await _writeSelection(normalized);
      return normalized;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      final normalized = await _normalizeSelection(const LlmSelectionState());
      await _writeSelection(normalized);
      return normalized;
    }

    final normalized = await _normalizeSelection(
      LlmSelectionState.fromJson(decoded),
    );
    await _writeSelection(normalized);
    return normalized;
  }

  Future<void> saveSelectionState(LlmSelectionState selection) async {
    final normalized = await _normalizeSelection(selection);
    await _writeSelection(normalized);
  }

  Future<bool?> getRuntimeImageInputSupport({
    required String providerId,
    required String modelId,
  }) async {
    final raw = _preferences.getString(_runtimeImageInputSupportKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final value = decoded[_runtimeImageInputSupportEntryKey(
      providerId: providerId,
      modelId: modelId,
    )];
    return value is bool ? value : null;
  }

  Future<void> saveRuntimeImageInputSupport({
    required String providerId,
    required String modelId,
    required bool supportsImageInput,
  }) async {
    final raw = _preferences.getString(_runtimeImageInputSupportKey);
    final nextMap = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        nextMap.addAll(decoded);
      }
    }
    nextMap[_runtimeImageInputSupportEntryKey(
      providerId: providerId,
      modelId: modelId,
    )] = supportsImageInput;
    await _preferences.setString(
      _runtimeImageInputSupportKey,
      jsonEncode(nextMap),
    );
  }

  Future<String?> getThemeId() async {
    return getThemeIdSync();
  }

  String? getThemeIdSync() {
    final value = _preferences.getString(_themeIdKey)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> saveThemeId(String themeId) async {
    await _preferences.setString(_themeIdKey, themeId.trim());
  }

  String _runtimeImageInputSupportEntryKey({
    required String providerId,
    required String modelId,
  }) {
    return '${providerId.trim()}::${modelId.trim()}';
  }

  Future<void> selectProviderAndModel({
    required String providerId,
    required String modelId,
  }) async {
    final current = await getSelectionState();
    await saveSelectionState(
      current.copyWith(
        selectedProviderId: providerId,
        selectedModelId: modelId,
      ),
    );
  }

  Future<void> setDefaultProviderAndModel({
    required String providerId,
    required String modelId,
  }) async {
    final current = await getSelectionState();
    await saveSelectionState(
      current.copyWith(
        defaultProviderId: providerId,
        defaultModelId: modelId,
      ),
    );
  }

  Future<String> getApiKey() async {
    final config = await getLlmConfig();
    return config.apiKey;
  }

  Future<String> getBaseUrl() async {
    final config = await getLlmConfig();
    return config.apiUrl;
  }

  Future<String> getModel() async {
    final config = await getLlmConfig();
    return config.model;
  }

  Future<SpeechInputConfig?> getSpeechInputConfig() async {
    final localDefaults = await _getLocalDefaults();
    return localDefaults?.speechInput;
  }

  Future<LLMConfig> getLlmConfig() async {
    final providers = await getProviders();
    if (providers.isEmpty) {
      throw Exception('请先在设置中新增提供方');
    }

    final selection = await getSelectionState();
    final resolvedProvider = _resolveProvider(
      providers,
      selection.selectedProviderId,
      fallbackProviderId: selection.defaultProviderId,
    );
    if (resolvedProvider == null) {
      throw Exception('请先在设置中新增提供方');
    }

    final resolvedModel = _resolveModel(
      resolvedProvider,
      selection.selectedModelId,
      fallbackModelId: selection.defaultModelId,
    );
    if (resolvedModel == null) {
      throw Exception('请先在设置中为当前提供方配置模型');
    }

    final localDefaults = await _getLocalDefaults();
    final additionalConfig = <String, dynamic>{
      ...?localDefaults?.additionalConfig,
    };

    return LLMConfig(
      apiKey: resolvedProvider.apiKey,
      apiUrl: resolvedProvider.baseUrl,
      model: resolvedModel.id,
      additionalConfig: {
        ...additionalConfig,
        'llm.selected_provider_id': resolvedProvider.id,
        'llm.selected_model_id': resolvedModel.id,
        'llm.selected_model_supports_image_input':
            resolvedModel.supportsImageInput,
        'llm.runtime_selected_model_supports_image_input':
            await getRuntimeImageInputSupport(
          providerId: resolvedProvider.id,
          modelId: resolvedModel.id,
        ),
      },
    );
  }

  Future<void> saveLlmConfig({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final trimmedApiKey = apiKey.trim();
    final trimmedBaseUrl = baseUrl.trim();
    final trimmedModel = model.trim();
    final providers = [...await getProviders()];
    final selection = await getSelectionState();
    final provider = _resolveProvider(
          providers,
          selection.selectedProviderId,
          fallbackProviderId: selection.defaultProviderId,
        ) ??
        LlmProviderConfig(
          id: _defaultProviderId,
          name: 'Default Provider',
          apiKey: trimmedApiKey,
          baseUrl: trimmedBaseUrl,
          models: [
            LlmProviderModel(id: trimmedModel, name: trimmedModel),
          ],
        );

    final updatedModels = [...provider.models];
    if (trimmedModel.isNotEmpty &&
        updatedModels.every((item) => item.id != trimmedModel)) {
      updatedModels.add(LlmProviderModel(id: trimmedModel, name: trimmedModel));
    }

    final updatedProvider = LlmProviderConfig(
      id: provider.id,
      name: provider.name,
      apiKey: trimmedApiKey,
      baseUrl: trimmedBaseUrl,
      models: updatedModels,
    );

    final index = providers.indexWhere((item) => item.id == updatedProvider.id);
    if (index >= 0) {
      providers[index] = updatedProvider;
    } else {
      providers.add(updatedProvider);
    }

    await _writeProviders(providers);
    await saveSelectionState(
      selection.copyWith(
        selectedProviderId: updatedProvider.id,
        selectedModelId: trimmedModel.isEmpty ? _defaultModelName : trimmedModel,
        defaultProviderId: selection.defaultProviderId ?? updatedProvider.id,
        defaultModelId: selection.defaultModelId ?? trimmedModel,
      ),
    );

    await _preferences.remove(_legacyApiKeyKey);
    await _preferences.remove(_legacyBaseUrlKey);
    await _preferences.remove(_legacyModelKey);
  }

  Future<String?> getToolExecutionModeName() async {
    final value = _preferences.getString(_toolExecutionModeKey)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> saveToolExecutionModeName(String modeName) async {
    await _preferences.setString(_toolExecutionModeKey, modeName.trim());
  }

  Future<Set<String>> getTrustedToolNames() async {
    final values = _preferences.getStringList(_trustedToolNamesKey) ?? const [];
    return values.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
  }

  Future<void> addTrustedToolName(String toolName) async {
    final trustedTools = await getTrustedToolNames();
    trustedTools.add(toolName.trim());
    await _preferences.setStringList(
      _trustedToolNamesKey,
      trustedTools.toList()..sort(),
    );
  }

  Future<void> removeTrustedToolName(String toolName) async {
    final trustedTools = await getTrustedToolNames();
    trustedTools.remove(toolName.trim());
    await _preferences.setStringList(
      _trustedToolNamesKey,
      trustedTools.toList()..sort(),
    );
  }

  Future<Set<String>> getBlockedToolNames() async {
    final values = _preferences.getStringList(_blockedToolNamesKey) ?? const [];
    return values.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
  }

  Future<void> addBlockedToolName(String toolName) async {
    final blockedTools = await getBlockedToolNames();
    blockedTools.add(toolName.trim());
    await _preferences.setStringList(
      _blockedToolNamesKey,
      blockedTools.toList()..sort(),
    );
  }

  Future<void> removeBlockedToolName(String toolName) async {
    final blockedTools = await getBlockedToolNames();
    blockedTools.remove(toolName.trim());
    await _preferences.setStringList(
      _blockedToolNamesKey,
      blockedTools.toList()..sort(),
    );
  }

  Future<Set<String>> getDisabledSkillIds() async {
    final values = _preferences.getStringList(_disabledSkillIdsKey) ?? const [];
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<void> disableSkillId(String skillId) async {
    final disabled = await getDisabledSkillIds();
    disabled.add(skillId.trim());
    await _preferences.setStringList(
      _disabledSkillIdsKey,
      disabled.toList()..sort(),
    );
  }

  Future<void> enableSkillId(String skillId) async {
    final disabled = await getDisabledSkillIds();
    disabled.remove(skillId.trim());
    await _preferences.setStringList(
      _disabledSkillIdsKey,
      disabled.toList()..sort(),
    );
  }

  Future<String?> getLatestSkillInstallUrl() async {
    final value = _preferences.getString(_latestSkillInstallUrlKey)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> saveLatestSkillInstallUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await _preferences.remove(_latestSkillInstallUrlKey);
      return;
    }
    await _preferences.setString(_latestSkillInstallUrlKey, trimmed);
  }

  /// Returns the Chat Completions adapter type: `'sdk'` (default) or `'legacy'`.
  ///
  /// `legacy` 仅用于极端兼容排障，默认不应再作为日常维护或功能优化目标。
  Future<String> getChatCompletionsAdapterType() async {
    return _preferences.getString(_chatCompletionsAdapterKey) ?? 'sdk';
  }

  Future<void> setChatCompletionsAdapterType(String type) async {
    await _preferences.setString(_chatCompletionsAdapterKey, type);
  }

  Future<DuplicateSkillInvocationMode> getDuplicateSkillInvocationMode() async {
    final raw = _preferences.getString(_duplicateSkillInvocationModeKey)?.trim();
    if (raw == null || raw.isEmpty) {
      return DuplicateSkillInvocationMode.reuse;
    }
    for (final mode in DuplicateSkillInvocationMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return DuplicateSkillInvocationMode.reuse;
  }

  Future<void> saveDuplicateSkillInvocationMode(
    DuplicateSkillInvocationMode mode,
  ) async {
    await _preferences.setString(_duplicateSkillInvocationModeKey, mode.name);
  }

  Future<void> _writeProviders(List<LlmProviderConfig> providers) async {
    await _preferences.setString(
      _providersJsonKey,
      jsonEncode(providers.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> _writeSelection(LlmSelectionState selection) async {
    await _preferences.setString(_selectionJsonKey, jsonEncode(selection.toJson()));
  }

  Future<LlmSelectionState> _normalizeSelection(
    LlmSelectionState selection, {
    List<LlmProviderConfig>? providers,
  }) async {
    final availableProviders = providers ?? await getProviders();
    if (availableProviders.isEmpty) {
      return const LlmSelectionState();
    }

    final defaultProvider = _resolveProvider(
          availableProviders,
          selection.defaultProviderId,
        ) ??
        availableProviders.first;
    final defaultModel = _resolveModel(
      defaultProvider,
      selection.defaultModelId,
    );

    final selectedProvider = _resolveProvider(
          availableProviders,
          selection.selectedProviderId,
          fallbackProviderId: defaultProvider.id,
        ) ??
        defaultProvider;
    final selectedModel = _resolveModel(
      selectedProvider,
      selection.selectedModelId,
      fallbackModelId:
              selectedProvider.id == defaultProvider.id ? defaultModel?.id : null,
    );

    return LlmSelectionState(
      selectedProviderId: selectedProvider.id,
      selectedModelId: selectedModel?.id,
      defaultProviderId: defaultProvider.id,
      defaultModelId: defaultModel?.id,
    );
  }

  LlmProviderConfig? _resolveProvider(
    List<LlmProviderConfig> providers,
    String? providerId, {
    String? fallbackProviderId,
  }) {
    for (final candidate in [providerId, fallbackProviderId]) {
      if (candidate == null) {
        continue;
      }
      for (final provider in providers) {
        if (provider.id == candidate) {
          return provider;
        }
      }
    }
    return providers.isEmpty ? null : providers.first;
  }

  LlmProviderModel? _resolveModel(
    LlmProviderConfig provider,
    String? modelId, {
    String? fallbackModelId,
  }) {
    for (final candidate in [modelId, fallbackModelId]) {
      if (candidate == null) {
        continue;
      }
      for (final model in provider.models) {
        if (model.id == candidate) {
          return model;
        }
      }
    }
    return provider.models.isEmpty ? null : provider.models.first;
  }
}
