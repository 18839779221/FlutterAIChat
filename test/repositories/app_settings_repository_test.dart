import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsRepository provider-first settings', () {
    test('seeds providers from local defaults on first read', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'aigocode',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'aigocode',
              name: 'AIGoCode',
              apiKey: 'local-key',
              baseUrl: 'https://api.aigocode.com',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
          ],
        ),
      );

      final providers = await repository.getProviders();
      final selection = await repository.getSelectionState();
      final config = await repository.getLlmConfig();

      expect(providers, hasLength(1));
      expect(providers.single.id, 'aigocode');
      expect(selection.selectedProviderId, 'aigocode');
      expect(selection.selectedModelId, 'gpt-5.4');
      expect(config.apiKey, 'local-key');
      expect(config.apiUrl, 'https://api.aigocode.com');
      expect(config.model, 'gpt-5.4');
    });

    test('saved providers and selection override local defaults after seeding',
        () async {
      SharedPreferences.setMockInitialValues({
        'llm.providers_seeded': true,
        'llm.providers_json':
            '[{"id":"saved","name":"Saved","apiKey":"saved-key","baseUrl":"https://saved.example","models":[{"id":"saved-model","name":"Saved Model"}]}]',
        'llm.selection_json':
            '{"selected_provider_id":"saved","selected_model_id":"saved-model","default_provider_id":"saved","default_model_id":"saved-model"}',
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'local',
          defaultModelId: 'local-model',
          providers: [
            LlmProviderConfig(
              id: 'local',
              name: 'Local',
              apiKey: 'local-key',
              baseUrl: 'https://local.example',
              models: [
                LlmProviderModel(id: 'local-model', name: 'Local Model'),
              ],
            ),
          ],
        ),
      );

      final providers = await repository.getProviders();
      final config = await repository.getLlmConfig();

      expect(providers.single.id, 'saved');
      expect(config.apiKey, 'saved-key');
      expect(config.apiUrl, 'https://saved.example');
      expect(config.model, 'saved-model');
    });

    test('can save provider and update current selection', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      );

      await repository.saveProvider(
        const LlmProviderConfig(
          id: 'aigocode',
          name: 'AIGoCode',
          apiKey: 'key',
          baseUrl: 'https://api.aigocode.com',
          models: [
            LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
            LlmProviderModel(id: 'gpt-5-mini', name: 'GPT-5 Mini'),
          ],
        ),
      );
      await repository.selectProviderAndModel(
        providerId: 'aigocode',
        modelId: 'gpt-5-mini',
      );

      final selection = await repository.getSelectionState();
      final config = await repository.getLlmConfig();

      expect(selection.selectedProviderId, 'aigocode');
      expect(selection.selectedModelId, 'gpt-5-mini');
      expect(config.model, 'gpt-5-mini');
    });

    test('falls back to first provider model when selected model disappears',
        () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      );

      await repository.saveProvider(
        const LlmProviderConfig(
          id: 'aigocode',
          name: 'AIGoCode',
          apiKey: 'key',
          baseUrl: 'https://api.aigocode.com',
          models: [
            LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
            LlmProviderModel(id: 'gpt-5-mini', name: 'GPT-5 Mini'),
          ],
        ),
      );
      await repository.selectProviderAndModel(
        providerId: 'aigocode',
        modelId: 'gpt-5-mini',
      );

      await repository.saveProvider(
        const LlmProviderConfig(
          id: 'aigocode',
          name: 'AIGoCode',
          apiKey: 'key',
          baseUrl: 'https://api.aigocode.com',
          models: [
            LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
          ],
        ),
      );

      final selection = await repository.getSelectionState();
      final config = await repository.getLlmConfig();

      expect(selection.selectedModelId, 'gpt-5.4');
      expect(config.model, 'gpt-5.4');
    });

    test('loads tavily web search config from local defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'aigocode',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'aigocode',
              name: 'AIGoCode',
              apiKey: 'local-key',
              baseUrl: 'https://local.example/v1',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
          ],
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

    test('loads speech input config from local defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'aigocode',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'aigocode',
              name: 'AIGoCode',
              apiKey: 'local-key',
              baseUrl: 'https://local.example/v1',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
          ],
          speechInput: SpeechInputConfig(
            enabled: true,
            provider: 'aliyun',
            endpoint: 'wss://speech.example/ws',
            apiKey: 'speech-key',
            sampleRate: 16000,
            languageHints: ['zh', 'en'],
          ),
        ),
      );

      final config = await repository.getSpeechInputConfig();

      expect(config, isNotNull);
      expect(config!.enabled, isTrue);
      expect(config.provider, 'aliyun');
      expect(config.endpoint, 'wss://speech.example/ws');
      expect(config.apiKey, 'speech-key');
      expect(config.sampleRate, 16000);
      expect(config.languageHints, const ['zh', 'en']);
    });

    test('returns null when speech input config is absent', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => const LlmLocalDefaults(
          defaultProviderId: 'aigocode',
          defaultModelId: 'gpt-5.4',
          providers: [
            LlmProviderConfig(
              id: 'aigocode',
              name: 'AIGoCode',
              apiKey: 'local-key',
              baseUrl: 'https://local.example/v1',
              models: [
                LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
              ],
            ),
          ],
        ),
      );

      final config = await repository.getSpeechInputConfig();

      expect(config, isNull);
    });
  });
}
