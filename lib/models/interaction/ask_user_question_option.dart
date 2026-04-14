/// One selectable option shown in an AskUserQuestion card.
class AskUserQuestionOption {
  /// Human-facing label rendered in the picker UI.
  final String label;

  /// Short helper copy describing when or why to choose this option.
  final String description;

  /// Whether this option should be visually emphasized as recommended.
  final bool isRecommended;

  const AskUserQuestionOption({
    required this.label,
    required this.description,
    required this.isRecommended,
  });

  factory AskUserQuestionOption.fromJson(Map<String, dynamic> json) {
    final rawLabel = (json['label'] as String? ?? '').trim();
    if (rawLabel.isEmpty) {
      throw const FormatException('label is required');
    }
    final parsed = _parseRecommended(rawLabel);
    return AskUserQuestionOption(
      label: parsed.label,
      description: (json['description'] as String? ?? '').trim(),
      isRecommended: json['isRecommended'] as bool? ?? parsed.isRecommended,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'description': description,
      'isRecommended': isRecommended,
    };
  }

  static ({String label, bool isRecommended}) _parseRecommended(String label) {
    const suffix = '(Recommended)';
    final trimmed = label.trim();
    if (!trimmed.endsWith(suffix)) {
      return (label: trimmed, isRecommended: false);
    }
    final normalized = trimmed.substring(0, trimmed.length - suffix.length).trim();
    return (label: normalized, isRecommended: true);
  }
}
