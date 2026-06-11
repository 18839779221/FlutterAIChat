import 'model_capability_override.dart';

class LlmProviderModel {
  /// Stable model identifier sent directly to the upstream API.
  final String id;

  /// Optional user-facing label shown in settings and model management UI.
  /// When empty, the UI should fall back to the model id.
  final String name;

  /// Whether this concrete model entry is known to support image input.
  final bool supportsImageInput;

  /// Whether this concrete model entry is known to support image generation.
  final bool supportsImageGeneration;

  /// Optional local capability limits attached to this concrete model entry.
  final ModelCapabilityOverride? capabilityOverride;

  const LlmProviderModel({
    required this.id,
    required this.name,
    this.supportsImageInput = false,
    this.supportsImageGeneration = false,
    this.capabilityOverride,
  });

  factory LlmProviderModel.fromJson(Map<String, dynamic> json) {
    final capabilityOverride = ModelCapabilityOverride.fromJson(json);
    return LlmProviderModel(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      supportsImageInput: json['supportsImageInput'] == true ||
          json['supports_image_input'] == true,
      supportsImageGeneration: json['supportsImageGeneration'] == true ||
          json['supports_image_generation'] == true,
      capabilityOverride:
          capabilityOverride.isEmpty ? null : capabilityOverride,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'supportsImageInput': supportsImageInput,
      'supportsImageGeneration': supportsImageGeneration,
      ...?capabilityOverride?.toJson(),
    };
  }

  /// Effective label used by UI when a custom name is absent.
  String get displayName => name.isEmpty ? id : name;
}
