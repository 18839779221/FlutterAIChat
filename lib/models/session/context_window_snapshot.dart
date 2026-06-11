import 'context_usage_category.dart';
import 'context_usage_top_item.dart';
import 'context_window_segment.dart';
import '../llm/model_capability_source_kind.dart';

class ContextWindowSnapshot {
  /// Runtime model name used to resolve the current budget profile.
  final String modelName;

  /// Provider-advertised or app-safe context window upper bound.
  final int maxContextTokens;

  /// Formal planner-visible input budget after reserves and provider caps.
  final int effectiveInputBudget;

  /// Formal token threshold that triggers auto compaction.
  final int autoCompactTriggerTokens;

  /// Estimated total tokens that would be sent as planner input.
  final int totalEstimatedInputTokens;

  /// Share of the auto-compaction trigger currently consumed by planner input.
  final double plannerInputUsageRatio;

  /// Share of the full context window currently consumed by planner input.
  final double totalWindowUsageRatio;

  /// Share of the formal effective input budget currently consumed.
  final double effectiveInputUsageRatio;

  /// Total context tokens currently occupied by planner input and reserves.
  final int usedWindowTokens;

  /// Share of the full context window currently occupied by planner input and reserves.
  final double usedWindowRatio;

  /// Whether older history was compacted into snapshot summary during build.
  final bool didCompactHistory;

  /// Last turn covered by the active snapshot summary, when present.
  final int? snapshotCoveredUntilTurnId;

  /// Number of completed turns still retained in raw recent form.
  final int recentCompletedTurnCount;

  /// Source of the capability facts used to derive this snapshot budget.
  final ModelCapabilitySourceKind? capabilitySource;

  /// Ordered context and reserve segments rendered by the UI.
  final List<ContextWindowSegment> segments;

  /// User-facing usage categories rendered in the main summary panel.
  final List<ContextUsageCategory> categories;

  /// Top heavy tool/web/file results shown as concrete high-cost items.
  final List<ContextUsageTopItem> topItems;

  const ContextWindowSnapshot({
    required this.modelName,
    required this.maxContextTokens,
    required this.effectiveInputBudget,
    required this.autoCompactTriggerTokens,
    required this.totalEstimatedInputTokens,
    required this.plannerInputUsageRatio,
    required this.totalWindowUsageRatio,
    required this.effectiveInputUsageRatio,
    this.usedWindowTokens = 0,
    this.usedWindowRatio = 0,
    required this.didCompactHistory,
    this.snapshotCoveredUntilTurnId,
    required this.recentCompletedTurnCount,
    this.capabilitySource,
    required this.segments,
    this.categories = const [],
    this.topItems = const [],
  });
}
