enum ContextUsageCategoryType {
  recentConversation,
  toolResults,
  historySummary,
  systemSettings,
}

class ContextUsageCategory {
  final ContextUsageCategoryType type;
  final String label;
  final int estimatedTokens;
  final double shareOfTotalWindow;
  final Map<String, Object?> details;

  const ContextUsageCategory({
    required this.type,
    required this.label,
    required this.estimatedTokens,
    required this.shareOfTotalWindow,
    this.details = const {},
  });
}
