import 'context_compaction_config.dart';

/// Budget profile describing the safe context strategy for one runtime model.
class ModelBudgetProfile {
  /// Stable runtime model identifier used for exact or family matching.
  final String modelId;

  /// Provider-advertised or app-safe context window upper bound.
  final int maxContextTokens;

  /// Tokens reserved for final visible output.
  final int reservedOutputTokens;

  /// Tokens reserved for hidden reasoning or provider continuation overhead.
  final int reasoningReserveTokens;

  /// Extra safety headroom kept unused to avoid edge overflows.
  final int safetyMarginTokens;

  /// Compaction thresholds paired with this model profile.
  final ContextCompactionConfig compactionConfig;

  const ModelBudgetProfile({
    required this.modelId,
    required this.maxContextTokens,
    required this.reservedOutputTokens,
    required this.reasoningReserveTokens,
    required this.safetyMarginTokens,
    this.compactionConfig = const ContextCompactionConfig(),
  });

  /// Remaining budget available to planner-visible input after reserves.
  int get usableInputBudget =>
      maxContextTokens -
      reservedOutputTokens -
      reasoningReserveTokens -
      safetyMarginTokens;

  ModelBudgetProfile copyWith({
    String? modelId,
    int? maxContextTokens,
    int? reservedOutputTokens,
    int? reasoningReserveTokens,
    int? safetyMarginTokens,
    ContextCompactionConfig? compactionConfig,
  }) {
    return ModelBudgetProfile(
      modelId: modelId ?? this.modelId,
      maxContextTokens: maxContextTokens ?? this.maxContextTokens,
      reservedOutputTokens: reservedOutputTokens ?? this.reservedOutputTokens,
      reasoningReserveTokens:
          reasoningReserveTokens ?? this.reasoningReserveTokens,
      safetyMarginTokens: safetyMarginTokens ?? this.safetyMarginTokens,
      compactionConfig: compactionConfig ?? this.compactionConfig,
    );
  }
}
