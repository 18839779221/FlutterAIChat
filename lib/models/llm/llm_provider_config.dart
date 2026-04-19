import 'llm_provider_model.dart';

class LlmProviderConfig {
  /// Stable provider identifier used by persisted selection state.
  final String id;

  /// User-facing provider name shown in settings screens.
  final String name;

  /// API key sent when this provider is the active runtime source.
  final String apiKey;

  /// Base URL for this provider's OpenAI-compatible endpoint.
  final String baseUrl;

  /// Models currently exposed by this provider configuration.
  final List<LlmProviderModel> models;

  const LlmProviderConfig({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.models,
  });

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'];
    final models = rawModels is List
        ? rawModels
            .whereType<Map>()
            .map((item) => LlmProviderModel.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false)
        : const <LlmProviderModel>[];

    return LlmProviderConfig(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      apiKey: (json['apiKey'] as String? ?? json['api_key'] as String? ?? '').trim(),
      baseUrl:
          (json['baseUrl'] as String? ?? json['base_url'] as String? ?? '').trim(),
      models: models,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'models': models.map((item) => item.toJson()).toList(growable: false),
    };
  }
}
