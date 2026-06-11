import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmProviderModel', () {
    test('parses image generation support from camel and snake case keys', () {
      final camel = LlmProviderModel.fromJson(const {
        'id': 'gpt-image-2',
        'name': 'GPT Image 2',
        'supportsImageGeneration': true,
      });
      final snake = LlmProviderModel.fromJson(const {
        'id': 'gpt-image-2',
        'name': 'GPT Image 2',
        'supports_image_generation': true,
      });

      expect(camel.supportsImageGeneration, isTrue);
      expect(snake.supportsImageGeneration, isTrue);
    });

    test('serializes image generation support separately from image input', () {
      const model = LlmProviderModel(
        id: 'gpt-image-2',
        name: 'GPT Image 2',
        supportsImageInput: false,
        supportsImageGeneration: true,
      );

      expect(model.toJson()['supportsImageInput'], isFalse);
      expect(model.toJson()['supportsImageGeneration'], isTrue);
    });
  });
}
