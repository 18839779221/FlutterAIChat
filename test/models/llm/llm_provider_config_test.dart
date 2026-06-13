import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmProviderConfig', () {
    test('parses and serializes optional side model id', () {
      final config = LlmProviderConfig.fromJson(const {
        'id': 'claude',
        'name': 'Claude',
        'apiKey': 'test-key',
        'baseUrl': 'https://api.anthropic.com/v1/messages',
        'side_model_id': 'claude-haiku',
        'models': [
          {'id': 'claude-opus', 'name': 'Claude Opus'},
          {'id': 'claude-haiku', 'name': 'Claude Haiku'},
        ],
      });

      expect(config.sideModelId, 'claude-haiku');
      expect(config.toJson()['sideModelId'], 'claude-haiku');
    });

    test('drops blank side model id values', () {
      final config = LlmProviderConfig.fromJson(const {
        'id': 'claude',
        'name': 'Claude',
        'apiKey': 'test-key',
        'baseUrl': 'https://api.anthropic.com/v1/messages',
        'side_model_id': '   ',
        'models': [
          {'id': 'claude-opus', 'name': 'Claude Opus'},
        ],
      });

      expect(config.sideModelId, isNull);
    });

    test('stores side model id on direct construction', () {
      const config = LlmProviderConfig(
        id: 'claude',
        name: 'Claude',
        apiKey: 'test-key',
        baseUrl: 'https://api.anthropic.com/v1/messages',
        sideModelId: 'claude-haiku',
        models: [
          LlmProviderModel(id: 'claude-opus', name: 'Claude Opus'),
          LlmProviderModel(id: 'claude-haiku', name: 'Claude Haiku'),
        ],
      );

      expect(config.sideModelId, 'claude-haiku');
    });
  });
}
