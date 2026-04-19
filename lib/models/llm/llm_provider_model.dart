class LlmProviderModel {
  /// Stable model identifier sent directly to the upstream API.
  final String id;

  /// Optional user-facing label shown in settings and model management UI.
  /// When empty, the UI should fall back to the model id.
  final String name;

  const LlmProviderModel({
    required this.id,
    required this.name,
  });

  factory LlmProviderModel.fromJson(Map<String, dynamic> json) {
    return LlmProviderModel(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  /// Effective label used by UI when a custom name is absent.
  String get displayName => name.isEmpty ? id : name;
}
