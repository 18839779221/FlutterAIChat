class LlmSelectionState {
  /// Active provider used for new model requests.
  final String? selectedProviderId;

  /// Active model used for new model requests.
  final String? selectedModelId;

  /// Default provider chosen by the user for future fallbacks.
  final String? defaultProviderId;

  /// Default model chosen by the user for future fallbacks.
  final String? defaultModelId;

  const LlmSelectionState({
    this.selectedProviderId,
    this.selectedModelId,
    this.defaultProviderId,
    this.defaultModelId,
  });

  factory LlmSelectionState.fromJson(Map<String, dynamic> json) {
    String? normalize(dynamic value) {
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return LlmSelectionState(
      selectedProviderId: normalize(json['selected_provider_id']),
      selectedModelId: normalize(json['selected_model_id']),
      defaultProviderId: normalize(json['default_provider_id']),
      defaultModelId: normalize(json['default_model_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (selectedProviderId != null) 'selected_provider_id': selectedProviderId,
      if (selectedModelId != null) 'selected_model_id': selectedModelId,
      if (defaultProviderId != null) 'default_provider_id': defaultProviderId,
      if (defaultModelId != null) 'default_model_id': defaultModelId,
    };
  }

  LlmSelectionState copyWith({
    String? selectedProviderId,
    String? selectedModelId,
    String? defaultProviderId,
    String? defaultModelId,
    bool clearSelectedProviderId = false,
    bool clearSelectedModelId = false,
    bool clearDefaultProviderId = false,
    bool clearDefaultModelId = false,
  }) {
    return LlmSelectionState(
      selectedProviderId: clearSelectedProviderId
          ? null
          : selectedProviderId ?? this.selectedProviderId,
      selectedModelId:
          clearSelectedModelId ? null : selectedModelId ?? this.selectedModelId,
      defaultProviderId: clearDefaultProviderId
          ? null
          : defaultProviderId ?? this.defaultProviderId,
      defaultModelId:
          clearDefaultModelId ? null : defaultModelId ?? this.defaultModelId,
    );
  }
}
