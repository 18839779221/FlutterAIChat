import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm/llm_config.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../models/llm/llm_selection_state.dart';
import 'llm_local_defaults.dart';

class AppSettingsRepository {
  static const String _providersJsonKey = 'llm.providers_json';
  static const String _selectionJsonKey = 'llm.selection_json';
  static const String _providersSeededKey = 'llm.providers_seeded';
  static const String _toolExecutionModeKey = 'tool.execution_mode';
  static const String _trustedToolNamesKey = 'tool.trusted_names';
  static const String _blockedToolNamesKey = 'tool.blocked_names';
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
    await _writeSelection(
      LlmSelectionState(
        selectedProviderId: defaults.defaultProviderId ?? defaults.providers.first.id,
        selectedModelId: defaults.defaultModelId ?? defaults.providers.first.models.first.id,
        defaultProviderId: defaults.defaultProviderId ?? defaults.providers.first.id,
        defaultModelId: defaults.defaultModelId ?? defaults.providers.first.models.first.id,
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
              item.baseUrl.isNotEmpty &&
              item.models.isNotEmpty,
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
      additionalConfig: additionalConfig,
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
        ) ??
        defaultProvider.models.first;

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
              selectedProvider.id == defaultProvider.id ? defaultModel.id : null,
        ) ??
        selectedProvider.models.first;

    return LlmSelectionState(
      selectedProviderId: selectedProvider.id,
      selectedModelId: selectedModel.id,
      defaultProviderId: defaultProvider.id,
      defaultModelId: defaultModel.id,
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
