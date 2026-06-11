/// Optional locally-declared capability limits attached to one provider model.
class ModelCapabilityOverride {
  final int? contextWindowTotal;
  final int? maxInputTokens;
  final int? maxOutputTokens;

  const ModelCapabilityOverride({
    this.contextWindowTotal,
    this.maxInputTokens,
    this.maxOutputTokens,
  });

  factory ModelCapabilityOverride.fromJson(Map<String, dynamic> json) {
    return ModelCapabilityOverride(
      contextWindowTotal: _readInt(
        json['contextWindowTotal'] ?? json['context_window_total'],
      ),
      maxInputTokens: _readInt(
        json['maxInputTokens'] ?? json['max_input_tokens'],
      ),
      maxOutputTokens: _readInt(
        json['maxOutputTokens'] ?? json['max_output_tokens'],
      ),
    );
  }

  bool get isEmpty =>
      contextWindowTotal == null &&
      maxInputTokens == null &&
      maxOutputTokens == null;

  Map<String, dynamic> toJson() {
    return {
      if (contextWindowTotal != null) 'contextWindowTotal': contextWindowTotal,
      if (maxInputTokens != null) 'maxInputTokens': maxInputTokens,
      if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
    };
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
