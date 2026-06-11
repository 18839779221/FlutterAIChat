import '../session/model_budget_profile.dart';
import 'resolved_model_capability.dart';

/// Runtime budget derived from resolved capability facts and app policy.
class ResolvedModelBudget {
  final ResolvedModelCapability capability;
  final ModelBudgetProfile policy;

  const ResolvedModelBudget({
    required this.capability,
    required this.policy,
  });

  int get effectiveInputBudget {
    final contextWindow = capability.contextWindowTotal ?? policy.maxContextTokens;
    final usable = contextWindow -
        policy.reservedOutputTokens -
        policy.reasoningReserveTokens -
        policy.safetyMarginTokens;
    final providerCap = capability.maxInputTokens ?? policy.providerInputCap;
    if (providerCap == null) {
      return usable;
    }
    return providerCap < usable ? providerCap : usable;
  }

  int get plannerMaxOutputTokens =>
      _clampOutput(policy.reservedOutputTokens);

  int get summaryMaxOutputTokens => _clampOutput(
        policy.reservedOutputTokens + policy.reasoningReserveTokens,
      );

  int get sideTaskMaxOutputTokens => summaryMaxOutputTokens;

  int _clampOutput(int requested) {
    final upperLimit = capability.maxOutputTokens;
    if (upperLimit == null) {
      return requested;
    }
    return requested > upperLimit ? upperLimit : requested;
  }
}
