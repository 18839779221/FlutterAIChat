import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsRepository local defaults', () {
    test('falls back to local defaults when preferences are empty', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          apiKey: 'local-key',
          baseUrl: 'https://local.example/v1',
          model: 'gpt-5.4',
        ),
      );

      final config = await repository.getLlmConfig();

      expect(config.apiKey, 'local-key');
      expect(config.apiUrl, 'https://local.example/v1');
      expect(config.model, 'gpt-5.4');
    });

    test('saved preferences take precedence over local defaults', () async {
      SharedPreferences.setMockInitialValues({
        'llm.api_key': 'saved-key',
        'llm.base_url': 'https://saved.example/v1',
        'llm.model': 'saved-model',
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          apiKey: 'local-key',
          baseUrl: 'https://local.example/v1',
          model: 'local-model',
        ),
      );

      final config = await repository.getLlmConfig();

      expect(config.apiKey, 'saved-key');
      expect(config.apiUrl, 'https://saved.example/v1');
      expect(config.model, 'saved-model');
    });

    test('loads tavily web search config from local defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          apiKey: 'local-key',
          baseUrl: 'https://local.example/v1',
          model: 'gpt-5.4',
          additionalConfig: {
            'web_search.provider': 'tavily',
            'web_search.tavily_api_key': 'tavily-local-key',
            'web_search.tavily_base_url': 'https://api.tavily.com/search',
          },
        ),
      );

      final config = await repository.getLlmConfig();

      expect(config.additionalConfig['web_search.provider'], 'tavily');
      expect(
        config.additionalConfig['web_search.tavily_api_key'],
        'tavily-local-key',
      );
      expect(
        config.additionalConfig['web_search.tavily_base_url'],
        'https://api.tavily.com/search',
      );
    });
  });
}
