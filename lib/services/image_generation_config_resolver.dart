import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';

/// Runtime image generation provider configuration resolved outside the active
/// chat-model selection.
class ImageGenerationRuntimeConfig {
  /// Provider id that owns the image generation credentials.
  final String providerId;

  /// API key used only by the image generation adapter.
  final String apiKey;

  /// OpenAI-compatible base URL used to derive `/images/generations`.
  final String baseUrl;

  /// Default image model when the tool call omits `model`.
  final String model;

  /// Default generation quality when the tool call omits `quality`.
  final String qualityDefault;

  const ImageGenerationRuntimeConfig({
    required this.providerId,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.qualityDefault,
  });
}

/// Resolves image generation runtime config from explicit `image_generation`
/// settings instead of implicitly reusing the currently selected chat provider.
class ImageGenerationConfigResolver {
  const ImageGenerationConfigResolver();

  ImageGenerationRuntimeConfig? resolve({
    required List<LlmProviderConfig> providers,
    required Map<String, dynamic> additionalConfig,
  }) {
    final defaultProviderId = _readConfigString(
      additionalConfig,
      dottedKey: 'image_generation.default_provider_id',
      nestedKey: 'default_provider_id',
    );
    final defaultModelId = _readConfigString(
      additionalConfig,
      dottedKey: 'image_generation.default_model_id',
      nestedKey: 'default_model_id',
    );
    final candidates = _imageGenerationCandidates(providers);
    if (candidates.isEmpty) {
      return null;
    }

    final selected = (defaultProviderId != null && defaultModelId != null)
        ? candidates.where(
            (item) =>
                item.provider.id == defaultProviderId &&
                item.model.id == defaultModelId,
          )
        : candidates.length == 1
            ? candidates
            : const Iterable<_ImageGenerationCandidate>.empty();
    final candidate = selected.isEmpty ? null : selected.first;
    if (candidate == null ||
        candidate.provider.apiKey.trim().isEmpty ||
        candidate.provider.baseUrl.trim().isEmpty) {
      return null;
    }
    return ImageGenerationRuntimeConfig(
      providerId: candidate.provider.id,
      apiKey: candidate.provider.apiKey,
      baseUrl: candidate.provider.baseUrl.trim(),
      model: candidate.model.id,
      qualityDefault: _readConfigString(
            additionalConfig,
            dottedKey: 'image_generation.quality_default',
            nestedKey: 'quality_default',
          ) ??
          'low',
    );
  }

  List<_ImageGenerationCandidate> _imageGenerationCandidates(
    List<LlmProviderConfig> providers,
  ) {
    final candidates = <_ImageGenerationCandidate>[];
    for (final provider in providers) {
      for (final model in provider.models) {
        if (model.supportsImageGeneration) {
          candidates.add(
            _ImageGenerationCandidate(provider: provider, model: model),
          );
        }
      }
    }
    return candidates;
  }

  String? _readConfigString(
    Map<String, dynamic> config, {
    required String dottedKey,
    required String nestedKey,
  }) {
    final flat = _normalizeString(config[dottedKey]);
    if (flat != null) {
      return flat;
    }
    final nested = config['image_generation'];
    if (nested is Map) {
      return _normalizeString(nested[nestedKey]);
    }
    return null;
  }

  String? _normalizeString(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _ImageGenerationCandidate {
  final LlmProviderConfig provider;
  final LlmProviderModel model;

  const _ImageGenerationCandidate({
    required this.provider,
    required this.model,
  });
}
