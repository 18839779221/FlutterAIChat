import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/image_generation_config_resolver.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/generate_image_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes prompt with optional image generation options', () async {
    final handler = GenerateImageToolHandler(
      imageGenerator: _unusedImageGenerator,
      resolveRuntimeConfig: () async => const ImageGenerationRuntimeConfig(
        providerId: 'beehears',
        apiKey: 'key',
        baseUrl: 'https://example.com/v1',
        model: 'gpt-image-2',
        qualityDefault: 'low',
      ),
    );

    final resolution = await handler.normalizeArguments(
      rawArguments: const {'prompt': 'A small brass robot painting clouds'},
      userMessage: '帮我生成一张图',
      history: const <ChatMessage>[],
      now: DateTime(2026, 6, 12),
    );

    expect(resolution.isValid, isTrue);
    expect(
      resolution.normalizedArguments['prompt'],
      'A small brass robot painting clouds',
    );
    expect(resolution.normalizedArguments['model'], 'gpt-image-2');
    expect(resolution.normalizedArguments['provider'], 'beehears');
    expect(resolution.normalizedArguments['size'], '1024x1024');
    expect(resolution.normalizedArguments['quality'], 'low');
  });

  test('tool description tells planner to use low quality by default', () {
    final handler = GenerateImageToolHandler(
      imageGenerator: _unusedImageGenerator,
    );

    expect(handler.definition.descriptionForModel, contains('low quality'));
    expect(
      handler.definition.descriptionForModel,
      contains('explicitly asks for high quality'),
    );
    expect(
      handler.definition.argumentSchema!.properties['quality']?.description,
      contains('Defaults to low'),
    );
  });

  test('does not expose runtime credential fields to planner schema', () {
    final handler = GenerateImageToolHandler(
      imageGenerator: _unusedImageGenerator,
    );

    expect(handler.definition.parameters, isNot(contains('apiKey')));
    expect(handler.definition.parameters, isNot(contains('baseUrl')));
    expect(
      handler.definition.argumentSchema!.properties.keys,
      isNot(contains('apiKey')),
    );
    expect(
      handler.definition.argumentSchema!.properties.keys,
      isNot(contains('baseUrl')),
    );
  });

  test('rejects empty prompt', () async {
    final handler = GenerateImageToolHandler(
      imageGenerator: _unusedImageGenerator,
    );

    final resolution = await handler.normalizeArguments(
      rawArguments: const {'prompt': '   '},
      userMessage: '生成图片',
      history: const <ChatMessage>[],
      now: DateTime(2026, 6, 12),
    );

    expect(resolution.isValid, isFalse);
    expect(resolution.errorCode, 'invalid_prompt');
  });

  test('execute calls injected image generator with normalized arguments',
      () async {
    Map<String, dynamic>? captured;
    final handler = GenerateImageToolHandler(
      imageGenerator: ({
        required prompt,
        required model,
        required size,
        required quality,
        provider,
        apiKey,
        baseUrl,
      }) async {
        captured = {
          'prompt': prompt,
          'model': model,
          'size': size,
          'quality': quality,
          'provider': provider,
          'apiKey': apiKey,
          'baseUrl': baseUrl,
        };
        return const ToolResult(
          toolName: 'generate_image',
          status: ToolExecutionStatus.success,
          summary: '已生成图片',
        );
      },
    );

    final result = await handler.execute(
      ToolExecutionContext(
        groupId: 7,
        toolName: 'generate_image',
        arguments: const {
          'prompt': 'A calendar cover',
          'model': 'gpt-image-2',
          'size': '1024x1024',
          'quality': 'high',
          'provider': 'beehears',
          'apiKey': 'key-1',
          'baseUrl': 'https://api.openai.com/v1',
        },
        history: const <ChatMessage>[],
        now: DateTime(2026, 6, 12),
        cwd: '/',
      ),
    );

    expect(result.status, ToolExecutionStatus.success);
    expect(captured, {
      'prompt': 'A calendar cover',
      'model': 'gpt-image-2',
      'size': '1024x1024',
      'quality': 'high',
      'provider': 'beehears',
      'apiKey': 'key-1',
      'baseUrl': 'https://api.openai.com/v1',
    });
  });
}

Future<ToolResult> _unusedImageGenerator({
  required String prompt,
  required String? model,
  required String size,
  required String? quality,
  String? provider,
  String? apiKey,
  String? baseUrl,
}) async {
  throw UnimplementedError();
}
