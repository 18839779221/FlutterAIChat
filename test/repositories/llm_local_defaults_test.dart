import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmLocalDefaults', () {
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
  });
}
