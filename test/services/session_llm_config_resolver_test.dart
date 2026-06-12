import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/session_llm_config_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds LLMConfig from a session runtime config and provider catalog',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'openai',
        defaultModelId: 'gpt-5.4',
        providers: [
          LlmProviderConfig(
            id: 'anthropic',
            name: 'Anthropic',
            apiKey: 'anthropic-key',
            baseUrl: 'https://api.anthropic.com/v1/messages',
            apiStyle: ApiStyle.anthropicMessages,
            models: [
              LlmProviderModel(
                id: 'claude-sonnet-4-5',
                name: 'Claude Sonnet 4.5',
              ),
            ],
          ),
        ],
      ),
    );
    final resolver = SessionLlmConfigResolver(repository);

    final config = await resolver.resolve(
      SessionRuntimeConfig(
        groupId: 42,
        providerId: 'anthropic',
        modelId: 'claude-sonnet-4-5',
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
      ),
    );

    expect(config.apiKey, 'anthropic-key');
    expect(config.apiUrl, 'https://api.anthropic.com/v1/messages');
    expect(config.model, 'claude-sonnet-4-5');
    expect(config.apiStyle, ApiStyle.anthropicMessages);
    expect(config.additionalConfig['llm.selected_provider_id'], 'anthropic');
    expect(
      config.additionalConfig['llm.selected_model_id'],
      'claude-sonnet-4-5',
    );
  });

  test('resolves side slot config when session runtime provides one', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'primary-provider',
        defaultModelId: 'primary-model',
        providers: [
          LlmProviderConfig(
            id: 'primary-provider',
            name: 'Primary',
            apiKey: 'primary-key',
            baseUrl: 'https://primary.example/v1/chat/completions',
            apiStyle: ApiStyle.chatCompletions,
            models: [
              LlmProviderModel(id: 'primary-model', name: 'Primary Model'),
            ],
          ),
          LlmProviderConfig(
            id: 'side-provider',
            name: 'Side',
            apiKey: 'side-key',
            baseUrl: 'https://side.example/v1/messages',
            apiStyle: ApiStyle.anthropicMessages,
            models: [
              LlmProviderModel(id: 'side-model', name: 'Side Model'),
            ],
          ),
        ],
      ),
    );
    final resolver = SessionLlmConfigResolver(repository);

    final config = await resolver.resolve(
      SessionRuntimeConfig(
        groupId: 7,
        providerId: 'primary-provider',
        modelId: 'primary-model',
        providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        sideProviderId: 'side-provider',
        sideModelId: 'side-model',
        sideProviderStyle: ChatTurnProviderStyle.anthropicMessages,
      ),
      slot: SessionRuntimeSlot.side,
    );

    expect(config.apiKey, 'side-key');
    expect(config.apiUrl, 'https://side.example/v1/messages');
    expect(config.model, 'side-model');
    expect(config.apiStyle, ApiStyle.anthropicMessages);
  });

  test('side slot falls back to primary config when side binding is unset',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'primary-provider',
        defaultModelId: 'primary-model',
        providers: [
          LlmProviderConfig(
            id: 'primary-provider',
            name: 'Primary',
            apiKey: 'primary-key',
            baseUrl: 'https://primary.example/v1',
            apiStyle: ApiStyle.responses,
            models: [
              LlmProviderModel(id: 'primary-model', name: 'Primary Model'),
            ],
          ),
        ],
      ),
    );
    final resolver = SessionLlmConfigResolver(repository);

    final config = await resolver.resolve(
      SessionRuntimeConfig(
        groupId: 9,
        providerId: 'primary-provider',
        modelId: 'primary-model',
        providerStyle: ChatTurnProviderStyle.openaiResponses,
      ),
      slot: SessionRuntimeSlot.side,
    );

    expect(config.apiKey, 'primary-key');
    expect(config.apiUrl, 'https://primary.example/v1');
    expect(config.model, 'primary-model');
    expect(config.apiStyle, ApiStyle.responses);
  });
}
