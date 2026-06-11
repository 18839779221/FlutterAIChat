import '../models/chat_message.dart';
import '../models/context/planner_context_carrier.dart';
import '../models/llm/llm_config.dart';
import '../models/llm/model_capability_source_kind.dart';
import '../models/llm/resolved_model_budget.dart';
import '../models/session/model_budget_profile.dart';
import 'model_capability_resolver.dart';
import 'model_budget_registry.dart';

class SessionPlannerBudgetEvaluation {
  final int maxContextTokens;
  final int usableInputBudget;
  final int effectiveInputBudget;
  final ModelCapabilitySourceKind capabilitySource;
  final int fixedPrefixTokens;
  final int summaryTokens;
  final int recentTurnsTokens;
  final int currentTurnTokens;
  final int toolSchemaTokens;
  final int totalInputTokens;
  final int autoCompactTriggerTokens;
  final double plannerInputUsageRatio;
  final double effectiveInputUsageRatio;
  final bool shouldCompact;

  const SessionPlannerBudgetEvaluation({
    required this.maxContextTokens,
    required this.usableInputBudget,
    required this.effectiveInputBudget,
    required this.capabilitySource,
    required this.fixedPrefixTokens,
    required this.summaryTokens,
    required this.recentTurnsTokens,
    required this.currentTurnTokens,
    required this.toolSchemaTokens,
    required this.totalInputTokens,
    required this.autoCompactTriggerTokens,
    required this.plannerInputUsageRatio,
    required this.effectiveInputUsageRatio,
    required this.shouldCompact,
  });
}

class SessionTokenBudgetService {
  SessionTokenBudgetService({
    ModelBudgetRegistry? modelBudgetRegistry,
    ModelCapabilityResolver? modelCapabilityResolver,
  })  : _modelBudgetRegistry = modelBudgetRegistry ?? ModelBudgetRegistry(),
        _modelCapabilityResolver = modelCapabilityResolver;

  final ModelBudgetRegistry _modelBudgetRegistry;
  final ModelCapabilityResolver? _modelCapabilityResolver;

  ModelBudgetProfile resolveProfile(String modelName) =>
      _modelBudgetRegistry.resolve(modelName);

  ResolvedModelBudget resolveBudgetForModelName(String modelName) {
    final profile = resolveProfile(modelName);
    return ResolvedModelBudget(
      capability: _modelBudgetRegistry.resolveFallbackCapability(modelName),
      policy: profile,
    );
  }

  ResolvedModelBudget resolveCachedBudgetForRuntime(LLMConfig runtimeConfig) {
    final resolver = _modelCapabilityResolver;
    if (resolver == null) {
      return resolveBudgetForModelName(runtimeConfig.model);
    }
    return resolver.resolveCachedOrFallback(runtimeConfig);
  }

  Future<ResolvedModelBudget> resolveBudgetForRuntime(LLMConfig runtimeConfig) {
    final resolver = _modelCapabilityResolver;
    if (resolver == null) {
      return Future.value(resolveBudgetForModelName(runtimeConfig.model));
    }
    return resolver.resolveForRuntime(runtimeConfig);
  }

  SessionPlannerBudgetEvaluation evaluatePlannerBudget({
    String? modelName,
    LLMConfig? runtimeConfig,
    required int fixedPrefixTokens,
    required int summaryTokens,
    required int recentTurnsTokens,
    required int currentTurnTokens,
    int toolSchemaTokens = 0,
  }) {
    final resolvedBudget = runtimeConfig != null
        ? resolveCachedBudgetForRuntime(runtimeConfig)
        : resolveBudgetForModelName(modelName ?? '');
    return evaluatePlannerBudgetForResolvedBudget(
      resolvedBudget: resolvedBudget,
      fixedPrefixTokens: fixedPrefixTokens,
      summaryTokens: summaryTokens,
      recentTurnsTokens: recentTurnsTokens,
      currentTurnTokens: currentTurnTokens,
      toolSchemaTokens: toolSchemaTokens,
    );
  }

  SessionPlannerBudgetEvaluation evaluatePlannerBudgetForResolvedBudget({
    required ResolvedModelBudget resolvedBudget,
    required int fixedPrefixTokens,
    required int summaryTokens,
    required int recentTurnsTokens,
    required int currentTurnTokens,
    int toolSchemaTokens = 0,
  }) {
    final profile = resolvedBudget.policy;
    final usableInputBudget = profile.usableInputBudget;
    final effectiveInputBudget = resolvedBudget.effectiveInputBudget;
    final totalInputTokens = fixedPrefixTokens +
        summaryTokens +
        recentTurnsTokens +
        currentTurnTokens +
        toolSchemaTokens;
    final autoCompactTriggerTokens = (effectiveInputBudget -
            profile.compactionConfig.autoCompactBufferTokens)
        .clamp(0, effectiveInputBudget);
    final plannerInputUsageRatio = autoCompactTriggerTokens <= 0
        ? 1.0
        : totalInputTokens / autoCompactTriggerTokens;
    final effectiveInputUsageRatio = effectiveInputBudget <= 0
        ? 1.0
        : totalInputTokens / effectiveInputBudget;

    return SessionPlannerBudgetEvaluation(
      maxContextTokens: resolvedBudget.maxContextTokens,
      usableInputBudget: usableInputBudget,
      effectiveInputBudget: effectiveInputBudget,
      capabilitySource: resolvedBudget.capability.source,
      fixedPrefixTokens: fixedPrefixTokens,
      summaryTokens: summaryTokens,
      recentTurnsTokens: recentTurnsTokens,
      currentTurnTokens: currentTurnTokens,
      toolSchemaTokens: toolSchemaTokens,
      totalInputTokens: totalInputTokens,
      autoCompactTriggerTokens: autoCompactTriggerTokens,
      plannerInputUsageRatio: plannerInputUsageRatio,
      effectiveInputUsageRatio: effectiveInputUsageRatio,
      shouldCompact: totalInputTokens >= autoCompactTriggerTokens,
    );
  }

  int estimateTextTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    return trimmed.runes.fold<int>(0, (total, rune) {
      return total + (rune > 127 ? 2 : 1);
    });
  }

  int estimateMessagesTokens(List<ChatMessage> messages) {
    return messages.fold<int>(
      0,
      (total, message) => total + estimateTextTokens(message.text),
    );
  }

  int estimateCarriersTokens(List<PlannerContextCarrier> carriers) {
    return carriers.fold<int>(0, (total, c) => total + c.estimatedTokens);
  }
}
