import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm/llm_config.dart';

class AppSettingsRepository {
  static const String _apiKeyKey = 'llm.api_key';
  static const String _baseUrlKey = 'llm.base_url';
  static const String _modelKey = 'llm.model';
  static const String defaultBaseUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const String defaultModel = 'deepseek-chat';

  final SharedPreferences _preferences;

  AppSettingsRepository(this._preferences);

  Future<String> getApiKey() async {
    return _preferences.getString(_apiKeyKey) ?? '';
  }

  Future<String> getBaseUrl() async {
    return _preferences.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<String> getModel() async {
    return _preferences.getString(_modelKey) ?? defaultModel;
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
}
