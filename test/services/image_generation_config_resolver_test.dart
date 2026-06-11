import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/services/image_generation_config_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageGenerationConfigResolver', () {
    test('auto-selects the only model marked as image generation capable', () {
      const resolver = ImageGenerationConfigResolver();

      final config = resolver.resolve(
        providers: const [
          LlmProviderConfig(
            id: 'chat-provider',
            name: 'Chat Provider',
            apiKey: 'chat-key',
            baseUrl: 'https://chat.example/v1',
            models: [
              LlmProviderModel(id: 'chat-model', name: 'Chat Model'),
            ],
          ),
          LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-image-2',
                name: 'GPT Image 2',
                supportsImageGeneration: true,
              ),
            ],
          ),
        ],
        additionalConfig: const {
          'llm.selected_provider_id': 'chat-provider',
        },
      );

      expect(config, isNotNull);
      expect(config!.providerId, 'beehears');
      expect(config.model, 'gpt-image-2');
      expect(config.apiKey, 'image-key');
      expect(config.baseUrl, 'https://ai.beehears.com/v1');
      expect(config.qualityDefault, 'low');
    });

    test('uses explicit default when multiple image generation models exist',
        () {
      const resolver = ImageGenerationConfigResolver();

      final config = resolver.resolve(
        providers: const [
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'openai-key',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-image-1',
                name: 'GPT Image 1',
                supportsImageGeneration: true,
              ),
            ],
          ),
          LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-image-2',
                name: 'GPT Image 2',
                supportsImageGeneration: true,
              ),
            ],
          ),
        ],
        additionalConfig: const {
          'image_generation.default_provider_id': 'beehears',
          'image_generation.default_model_id': 'gpt-image-2',
          'image_generation.quality_default': 'low',
        },
      );

      expect(config, isNotNull);
      expect(config!.providerId, 'beehears');
      expect(config.model, 'gpt-image-2');
    });

    test('returns null when explicit default is not image generation capable',
        () {
      const resolver = ImageGenerationConfigResolver();

      final config = resolver.resolve(
        providers: const [
          LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(id: 'text-model', name: 'Text Model'),
            ],
          ),
        ],
        additionalConfig: const {
          'image_generation.default_provider_id': 'beehears',
          'image_generation.default_model_id': 'text-model',
        },
      );

      expect(config, isNull);
    });

    test('image input support does not imply image generation support', () {
      const resolver = ImageGenerationConfigResolver();

      final config = resolver.resolve(
        providers: const [
          LlmProviderConfig(
            id: 'vision-provider',
            name: 'Vision Provider',
            apiKey: 'vision-key',
            baseUrl: 'https://vision.example/v1',
            models: [
              LlmProviderModel(
                id: 'vision-model',
                name: 'Vision Model',
                supportsImageInput: true,
              ),
            ],
          ),
        ],
        additionalConfig: const {
          'llm.selected_provider_id': 'vision-provider',
        },
      );

      expect(config, isNull);
    });
  });
}
