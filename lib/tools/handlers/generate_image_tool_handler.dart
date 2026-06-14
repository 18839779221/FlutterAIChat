import '../../models/chat_message.dart';
import '../../models/tool/localized_tool_text.dart';
import '../../models/tool/tool_argument_property.dart';
import '../../models/tool/tool_argument_schema.dart';
import '../../models/tool/tool_definition.dart';
import '../../services/image_generation_config_resolver.dart';
import '../../services/tool_executor.dart';
import '../core/tool_argument_resolution.dart';
import '../core/tool_execution_context.dart';
import '../core/tool_handler.dart';

/// Handles text-to-image generation through the configured image provider.
class GenerateImageToolHandler extends ToolHandler {
  GenerateImageToolHandler({
    required ImageGenerator imageGenerator,
    ImageGenerationRuntimeConfigResolver? resolveRuntimeConfig,
  })  : _imageGenerator = imageGenerator,
        _resolveRuntimeConfig = resolveRuntimeConfig;

  final ImageGenerator _imageGenerator;
  final ImageGenerationRuntimeConfigResolver? _resolveRuntimeConfig;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'generate_image',
        title: 'Generate Image',
        localizedTitle: LocalizedToolText(
          english: 'Generate Image',
          chinese: '生成图片',
        ),
        descriptionForModel:
            'Generate a new image from a text prompt when the user explicitly asks for image creation, illustration, visual assets, cover art, mockups, or other generated visual output. Use low quality by default to save cost and latency. Only set quality to high when the user explicitly asks for high quality, HD, high resolution, print quality, or similar. Do not use this for image understanding or when the user only asks how to generate images.',
        localizedDescriptionForModel: LocalizedToolText(
          english:
              'Generate a new image from a text prompt when the user explicitly asks for image creation, illustration, visual assets, cover art, mockups, or other generated visual output. Use low quality by default to save cost and latency. Only set quality to high when the user explicitly asks for high quality, HD, high resolution, print quality, or similar. Do not use this for image understanding or when the user only asks how to generate images.',
          chinese:
              '当用户明确要求生成图片、插图、视觉素材、封面、视觉稿或其他图片输出时使用。默认使用 low 质量以节省成本和等待时间。只有当用户明确要求高质量、高清、高分辨率、印刷质量或类似需求时，才把 quality 设为 high。不要用于图片理解，也不要在用户只是询问如何生成图片时调用。',
        ),
        isConcurrencySafe: false,
        parameters: {
          'prompt': 'string',
          'model': 'string?',
          'size': 'string?',
          'quality': 'string?',
        },
        argumentSchema: ToolArgumentSchema(
          properties: {
            'prompt': ToolArgumentProperty.string(
              description: 'Detailed prompt describing the image to generate.',
              localizedDescription: LocalizedToolText(
                english: 'Detailed prompt describing the image to generate.',
                chinese: '描述要生成图片的详细提示词。',
              ),
            ),
            'model': ToolArgumentProperty.string(
              description: 'Optional image model id. Defaults to gpt-image-2.',
              localizedDescription: LocalizedToolText(
                english: 'Optional image model id. Defaults to gpt-image-2.',
                chinese: '可选图片模型 ID。默认使用 gpt-image-2。',
              ),
            ),
            'size': ToolArgumentProperty.string(
              description: 'Optional output size. Defaults to 1024x1024.',
              localizedDescription: LocalizedToolText(
                english: 'Optional output size. Defaults to 1024x1024.',
                chinese: '可选输出尺寸。默认 1024x1024。',
              ),
            ),
            'quality': ToolArgumentProperty.string(
              description:
                  'Optional image quality. Defaults to low. Use high only when the user explicitly asks for high quality, HD, high resolution, print quality, or similar.',
              localizedDescription: LocalizedToolText(
                english:
                    'Optional image quality. Defaults to low. Use high only when the user explicitly asks for high quality, HD, high resolution, print quality, or similar.',
                chinese:
                    '可选图片质量。默认 low。只有用户明确要求高质量、高清、高分辨率、印刷质量或类似需求时才使用 high。',
              ),
            ),
          },
          required: ['prompt'],
        ),
      );

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    final prompt = rawArguments['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_prompt',
        errorSummary: '生成图片失败：缺少有效提示词',
      );
    }

    final runtimeConfig = await _resolveRuntimeConfig?.call();
    final resolvedModel =
        _readOptionalString(rawArguments['model']) ?? runtimeConfig?.model;
    final resolvedQuality = _readOptionalString(rawArguments['quality']) ??
        runtimeConfig?.qualityDefault;
    final resolvedProvider = runtimeConfig?.providerId;

    return ToolArgumentResolution.valid({
      'prompt': prompt.trim(),
      if (resolvedModel != null) 'model': resolvedModel,
      'size': _readOptionalString(rawArguments['size']) ?? '1024x1024',
      if (resolvedQuality != null) 'quality': resolvedQuality,
      if (resolvedProvider != null) 'provider': resolvedProvider,
    });
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) {
    return _imageGenerator(
      prompt: context.arguments['prompt'] as String,
      model: context.arguments['model'] as String?,
      size: context.arguments['size'] as String,
      quality: context.arguments['quality'] as String?,
      provider: context.arguments['provider'] as String?,
      apiKey: context.arguments['apiKey'] as String?,
      baseUrl: context.arguments['baseUrl'] as String?,
    );
  }

  String? _readOptionalString(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

typedef ImageGenerationRuntimeConfigResolver =
    Future<ImageGenerationRuntimeConfig?> Function();
