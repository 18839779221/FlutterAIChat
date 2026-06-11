import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmLocalDefaults', () {
    test('parses model capability overrides from provider model entries', () {
      final defaults = LlmLocalDefaults.fromJson({
        'providers': [
          {
            'id': 'openai',
            'name': 'OpenAI',
            'apiKey': 'k',
            'baseUrl': 'https://api.openai.com/v1',
            'models': [
              {
                'id': 'gpt-5',
                'name': 'GPT-5',
                'contextWindowTotal': 1000000,
                'maxInputTokens': 256000,
                'maxOutputTokens': 32000,
              },
            ],
          },
        ],
      });

      final model = defaults.providers.single.models.single;
      expect(model.capabilityOverride?.contextWindowTotal, 1000000);
      expect(model.capabilityOverride?.maxInputTokens, 256000);
      expect(model.capabilityOverride?.maxOutputTokens, 32000);
    });

    test('parses provider-first local defaults structure', () {
      final defaults = LlmLocalDefaults.fromJson({
        'default_provider_id': 'aigocode',
        'default_model_id': 'gpt-5.4',
        'providers': [
          {
            'id': 'aigocode',
            'name': 'AIGoCode',
            'api_key': 'test-key',
            'base_url': 'https://api.aigocode.com',
            'models': [
              {
                'id': 'gpt-5.4',
                'name': '',
              },
              {
                'id': 'gpt-5-mini',
                'name': '',
              },
            ],
          },
        ],
        'web_search': {
          'provider': 'tavily',
          'tavily_api_key': 'tvly-test',
        },
        'image_generation': {
          'default_provider_id': 'beehears',
          'default_model_id': 'gpt-image-2',
          'quality_default': 'low',
        },
      });

      expect(defaults.defaultProviderId, 'aigocode');
      expect(defaults.defaultModelId, 'gpt-5.4');
      expect(defaults.providers, hasLength(1));
      expect(defaults.providers.first.id, 'aigocode');
      expect(defaults.providers.first.models, hasLength(2));
      expect(defaults.providers.first.models.first.id, 'gpt-5.4');
      expect(defaults.providers.first.models.first.name, isEmpty);
      expect(defaults.providers.first.models.first.displayName, 'gpt-5.4');
      expect(defaults.additionalConfig['web_search.provider'], 'tavily');
      expect(
        defaults.additionalConfig['web_search.tavily_api_key'],
        'tvly-test',
      );
      expect(
        defaults.additionalConfig['image_generation.default_provider_id'],
        'beehears',
      );
      expect(
        defaults.additionalConfig['image_generation.default_model_id'],
        'gpt-image-2',
      );
      expect(
        defaults.additionalConfig['image_generation.quality_default'],
        'low',
      );
    });

    test('filters invalid providers and empty models', () {
      final defaults = LlmLocalDefaults.fromJson({
        'default_provider_id': 'missing',
        'default_model_id': 'missing',
        'providers': [
          {
            'id': '   ',
            'name': 'Invalid',
            'api_key': 'key',
            'base_url': 'https://invalid.example',
            'models': [
              {'id': 'gpt-5.4', 'name': 'GPT-5.4'},
            ],
          },
          {
            'id': 'valid',
            'name': 'Valid',
            'api_key': 'key',
            'base_url': 'https://valid.example',
            'models': [
              {'id': '  ', 'name': 'Missing id'},
              {'id': 'gpt-5.4', 'name': 'GPT-5.4'},
            ],
          },
          {
            'id': 'empty-models',
            'name': 'Empty Models',
            'api_key': 'key',
            'base_url': 'https://empty.example',
            'models': const [],
          },
        ],
      });

      expect(defaults.providers, hasLength(1));
      expect(defaults.providers.single.id, 'valid');
      expect(defaults.providers.single.models, hasLength(1));
      expect(defaults.providers.single.models.single.id, 'gpt-5.4');
      expect(defaults.isEmpty, isFalse);
    });

    test('parses speech input config with defaults', () {
      final defaults = LlmLocalDefaults.fromJson({
        'speechInput': {
          'enabled': true,
          'provider': 'aliyun',
          'endpoint': 'wss://speech.example/ws',
          'apiKey': 'speech-key',
        },
      });

      expect(defaults.speechInput, isNotNull);
      expect(defaults.speechInput!.enabled, isTrue);
      expect(defaults.speechInput!.provider, 'aliyun');
      expect(defaults.speechInput!.endpoint, 'wss://speech.example/ws');
      expect(defaults.speechInput!.apiKey, 'speech-key');
      expect(defaults.speechInput!.sampleRate, 16000);
      expect(defaults.speechInput!.languageHints, const ['zh', 'en']);
      expect(defaults.speechInput!.isValid, isTrue);
    });

    test('treats incomplete speech input config as invalid but readable', () {
      final defaults = LlmLocalDefaults.fromJson({
        'speechInput': {
          'enabled': true,
          'provider': 'aliyun',
          'endpoint': '   ',
          'apiKey': '',
          'sampleRate': 8000,
          'languageHints': ['zh'],
        },
      });

      expect(defaults.speechInput, isNotNull);
      expect(defaults.speechInput!.enabled, isTrue);
      expect(defaults.speechInput!.provider, 'aliyun');
      expect(defaults.speechInput!.endpoint, isEmpty);
      expect(defaults.speechInput!.apiKey, isEmpty);
      expect(defaults.speechInput!.sampleRate, 8000);
      expect(defaults.speechInput!.languageHints, const ['zh']);
      expect(defaults.speechInput!.isValid, isFalse);
    });
  });
}
