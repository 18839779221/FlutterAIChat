import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm/llm_config.dart';
import 'llm_local_defaults.dart';

class AppSettingsRepository {
  static const String _apiKeyKey = 'llm.api_key';
  static const String _baseUrlKey = 'llm.base_url';
  static const String _modelKey = 'llm.model';
  static const String _toolExecutionModeKey = 'tool.execution_mode';
  static const String _trustedToolNamesKey = 'tool.trusted_names';
  static const String defaultBaseUrl = '';
  static const String defaultModel = 'deepseek-chat';

  final SharedPreferences _preferences;
  final Future<LlmLocalDefaults?> Function()? _localDefaultsLoader;
  Future<LlmLocalDefaults?>? _cachedLocalDefaults;

  AppSettingsRepository(
    this._preferences, {
    Future<LlmLocalDefaults?> Function()? localDefaultsLoader,
  }) : _localDefaultsLoader = localDefaultsLoader ?? const AssetLlmLocalDefaultsLoader().load;

  String? _readSavedValue(String key) {
    final value = _preferences.getString(key)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<LlmLocalDefaults?> _getLocalDefaults() {
    return _cachedLocalDefaults ??= _localDefaultsLoader?.call() ?? Future.value(null);
  }

  Future<String> getApiKey() async {
    return _readSavedValue(_apiKeyKey) ?? (await _getLocalDefaults())?.apiKey?.trim() ?? '';
  }

  Future<String> getBaseUrl() async {
    return _readSavedValue(_baseUrlKey) ??
        (await _getLocalDefaults())?.baseUrl?.trim() ??
        defaultBaseUrl;
  }

  Future<String> getModel() async {
    return _readSavedValue(_modelKey) ??
        (await _getLocalDefaults())?.model?.trim() ??
        defaultModel;
  }

  Future<LLMConfig> getLlmConfig() async {
    return LLMConfig(
      apiKey: await getApiKey(),
      apiUrl: await getBaseUrl(),
      model: await getModel(),
    );
  }

  Future<void> saveLlmConfig({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    await _preferences.setString(_apiKeyKey, apiKey.trim());
    await _preferences.setString(_baseUrlKey, baseUrl.trim());
    await _preferences.setString(_modelKey, model.trim());
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
}
