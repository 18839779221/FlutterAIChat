class LlmSelectionState {
  /// Active provider used for new model requests.
  final String? selectedProviderId;

  /// Active model used for new model requests.
  final String? selectedModelId;

  const LlmSelectionState({
    this.selectedProviderId,
    this.selectedModelId,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (selectedProviderId != null) 'selected_provider_id': selectedProviderId,
      if (selectedModelId != null) 'selected_model_id': selectedModelId,
    };
  }

  LlmSelectionState copyWith({
    String? selectedProviderId,
    String? selectedModelId,
    bool clearSelectedProviderId = false,
    bool clearSelectedModelId = false,
  }) {
    return LlmSelectionState(
      selectedProviderId: clearSelectedProviderId
          ? null
          : selectedProviderId ?? this.selectedProviderId,
      selectedModelId:
          clearSelectedModelId ? null : selectedModelId ?? this.selectedModelId,
    );
  }
}
