import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_config.dart';
import '../models/llm/model_capability_source_kind.dart';
import '../models/llm/resolved_model_budget.dart';
import '../models/llm/resolved_model_capability.dart';
import '../repositories/app_settings_repository.dart';
import 'model_budget_registry.dart';

abstract class ModelCapabilitySource {
  Future<ResolvedModelCapability?> fetch(LLMConfig config);
}

/// Resolves runtime capability facts before budget policy is applied.
class ModelCapabilityResolver {
  ModelCapabilityResolver({
    required AppSettingsRepository settingsRepository,
    required ModelBudgetRegistry budgetRegistry,
    this.providerSources = const [],
    this.catalogSource,
  })  : _settingsRepository = settingsRepository,
        _budgetRegistry = budgetRegistry;

  final AppSettingsRepository _settingsRepository;
  final ModelBudgetRegistry _budgetRegistry;
  final List<ModelCapabilitySource> providerSources;
  final ModelCapabilitySource? catalogSource;

  ResolvedModelBudget resolveCachedOrFallback(LLMConfig config) {
    final capability = _resolveLocalOverrideCapability(config) ??
        _budgetRegistry.resolveFallbackCapability(config.model);
    final policy = _budgetRegistry.resolvePolicy(config.model);
    return ResolvedModelBudget(capability: capability, policy: policy);
  }

  Future<ResolvedModelBudget> resolveForRuntime(LLMConfig config) async {
    final overrideCapability = await _resolveLocalOverrideCapabilityAsync(
      config,
    );
    if (overrideCapability != null) {
      return ResolvedModelBudget(
        capability: overrideCapability,
        policy: _budgetRegistry.resolvePolicy(config.model),
      );
    }

    return resolveCachedOrFallback(config);
  }

  Future<void> refreshInBackground(LLMConfig config) async {
    final source = providerSources.isEmpty ? catalogSource : providerSources.first;
    if (source == null) {
      return;
    }
    await source.fetch(config);
  }

  ResolvedModelCapability? _resolveLocalOverrideCapability(LLMConfig config) {
    final providerId =
        (config.additionalConfig['llm.selected_provider_id'] as String?)
            ?.trim();
    final baseUrl =
        (config.additionalConfig['llm.selected_base_url'] as String?)
            ?.trim();
    final rawStyle =
        (config.additionalConfig['llm.selected_api_style'] as String?)?.trim();
    if (providerId == null ||
        providerId.isEmpty ||
        baseUrl == null ||
        baseUrl.isEmpty) {
      return null;
    }
    final override =
        _settingsRepository.getSelectedModelCapabilityOverrideSync();
    if (override == null || override.isEmpty) {
      return null;
    }
    return ResolvedModelCapability(
      providerId: providerId,
      providerStyle: _readApiStyle(rawStyle) ?? config.apiStyle ?? ApiStyle.chatCompletions,
      baseUrlFingerprint: baseUrl,
      modelId: config.model.trim(),
      contextWindowTotal: override.contextWindowTotal,
      maxInputTokens: override.maxInputTokens,
      maxOutputTokens: override.maxOutputTokens,
      source: ModelCapabilitySourceKind.localOverride,
    );
  }

  Future<ResolvedModelCapability?> _resolveLocalOverrideCapabilityAsync(
    LLMConfig config,
  ) async {
    final providerId =
        (config.additionalConfig['llm.selected_provider_id'] as String?)
            ?.trim();
    final baseUrl =
        (config.additionalConfig['llm.selected_base_url'] as String?)
            ?.trim();
    final rawStyle =
        (config.additionalConfig['llm.selected_api_style'] as String?)?.trim();
    if (providerId == null ||
        providerId.isEmpty ||
        baseUrl == null ||
        baseUrl.isEmpty) {
      return null;
    }
    final override =
        await _settingsRepository.getSelectedModelCapabilityOverride();
    if (override == null || override.isEmpty) {
      return null;
    }
    return ResolvedModelCapability(
      providerId: providerId,
      providerStyle:
          _readApiStyle(rawStyle) ?? config.apiStyle ?? ApiStyle.chatCompletions,
      baseUrlFingerprint: baseUrl,
      modelId: config.model.trim(),
      contextWindowTotal: override.contextWindowTotal,
      maxInputTokens: override.maxInputTokens,
      maxOutputTokens: override.maxOutputTokens,
      source: ModelCapabilitySourceKind.localOverride,
    );
  }

  ApiStyle? _readApiStyle(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    for (final style in ApiStyle.values) {
      if (style.name == rawValue) {
        return style;
      }
    }
    return null;
  }
}
