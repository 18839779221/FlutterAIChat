class ContextUsageTopItem {
  final String toolName;
  final String objectLabel;
  final int estimatedTokens;
  final double shareOfTotalWindow;
  final Map<String, Object?> details;

  const ContextUsageTopItem({
    required this.toolName,
    required this.objectLabel,
    required this.estimatedTokens,
    required this.shareOfTotalWindow,
    this.details = const {},
  });

  String get displayLabel {
    final trimmedObject = objectLabel.trim();
    if (trimmedObject.isEmpty) {
      return toolName.trim();
    }
    return '${toolName.trim()} · $trimmedObject';
  }
}
