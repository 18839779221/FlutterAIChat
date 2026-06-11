import 'dart:async';

import '../models/llm/api_protocol_resolver.dart';
import '../models/llm/llm_config.dart';
import '../models/llm/model_capability_source_kind.dart';
import '../models/llm/resolved_model_budget.dart';
import '../models/llm/resolved_model_capability.dart';
import '../repositories/app_settings_repository.dart';
import 'model_capability_sources/provider_model_capability_source.dart';
import 'model_budget_registry.dart';

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
  final List<ProviderModelCapabilitySource> providerSources;
  final ModelCapabilitySource? catalogSource;

  ResolvedModelBudget resolveCachedOrFallback(LLMConfig config) {
    final overrideCapability = _resolveLocalOverrideCapability(config);
    if (overrideCapability != null) {
      return ResolvedModelBudget(
        capability: overrideCapability,
        policy: _budgetRegistry.resolvePolicy(config.model),
      );
    }

    unawaited(refreshInBackground(config));
    final capability = _resolveCachedCapability(config) ??
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

    final policy = _budgetRegistry.resolvePolicy(config.model);
    final fallbackCapability = _budgetRegistry.resolveFallbackCapability(
      config.model,
    );
    final providerCapability = await _resolveProviderCapability(config);
    final catalogCapability =
        providerCapability == null || _isIncomplete(providerCapability)
            ? await _resolveCatalogCapability(config)
            : null;
    final resolvedCapability = _composeCapability(
      primary: providerCapability ?? catalogCapability,
      secondary: providerCapability == null ? null : catalogCapability,
      fallback: fallbackCapability,
    );
    if (resolvedCapability.source !=
        ModelCapabilitySourceKind.builtInFallback) {
      await _settingsRepository.saveModelCapabilityCache(resolvedCapability);
    }
    return ResolvedModelBudget(
      capability: resolvedCapability,
      policy: policy,
    );
  }

  Future<void> refreshInBackground(LLMConfig config) async {
    final overrideCapability = await _resolveLocalOverrideCapabilityAsync(
      config,
    );
    if (overrideCapability != null) {
      return;
    }
    try {
      await resolveForRuntime(config);
    } catch (_) {
      // Cached/fallback path must never be invalidated by refresh errors.
    }
  }

  ResolvedModelCapability? _resolveLocalOverrideCapability(LLMConfig config) {
    final providerId =
        (config.additionalConfig['llm.selected_provider_id'] as String?)
            ?.trim();
    final baseUrl =
        (config.additionalConfig['llm.selected_base_url'] as String?)?.trim();
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
      providerStyle: _readApiStyle(rawStyle) ??
          config.apiStyle ??
          ApiStyle.chatCompletions,
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
        (config.additionalConfig['llm.selected_base_url'] as String?)?.trim();
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
      providerStyle: _readApiStyle(rawStyle) ??
          config.apiStyle ??
          ApiStyle.chatCompletions,
      baseUrlFingerprint: baseUrl,
      modelId: config.model.trim(),
      contextWindowTotal: override.contextWindowTotal,
      maxInputTokens: override.maxInputTokens,
      maxOutputTokens: override.maxOutputTokens,
      source: ModelCapabilitySourceKind.localOverride,
    );
  }

  ResolvedModelCapability? _resolveCachedCapability(LLMConfig config) {
    final target = _readCapabilityTarget(config);
    if (target == null) {
      return null;
    }
    return _settingsRepository.getModelCapabilityCacheSync(
      providerId: target.providerId,
      providerStyle: target.providerStyle,
      baseUrlFingerprint: target.baseUrlFingerprint,
      modelId: target.modelId,
    );
  }

  Future<ResolvedModelCapability?> _resolveProviderCapability(
    LLMConfig config,
  ) async {
    for (final source in providerSources) {
      if (!source.supports(config)) {
        continue;
      }
      try {
        final capability = await source.fetch(config);
        if (capability != null) {
          return capability;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<ResolvedModelCapability?> _resolveCatalogCapability(
    LLMConfig config,
  ) async {
    final source = catalogSource;
    if (source == null) {
      return null;
    }
    try {
      return await source.fetch(config);
    } catch (_) {
      return null;
    }
  }

  bool _isIncomplete(ResolvedModelCapability capability) {
    return capability.contextWindowTotal == null ||
        capability.maxInputTokens == null ||
        capability.maxOutputTokens == null;
  }

  ResolvedModelCapability _composeCapability({
    required ResolvedModelCapability? primary,
    required ResolvedModelCapability? secondary,
    required ResolvedModelCapability fallback,
  }) {
    final chosen = primary ?? secondary ?? fallback;
    return ResolvedModelCapability(
      providerId: chosen.providerId,
      providerStyle: chosen.providerStyle,
      baseUrlFingerprint: chosen.baseUrlFingerprint,
      modelId: chosen.modelId,
      contextWindowTotal: primary?.contextWindowTotal ??
          secondary?.contextWindowTotal ??
          fallback.contextWindowTotal,
      maxInputTokens: primary?.maxInputTokens ??
          secondary?.maxInputTokens ??
          fallback.maxInputTokens,
      maxOutputTokens: primary?.maxOutputTokens ??
          secondary?.maxOutputTokens ??
          fallback.maxOutputTokens,
      source: chosen.source,
    );
  }

  _CapabilityTarget? _readCapabilityTarget(LLMConfig config) {
    final providerId =
        (config.additionalConfig['llm.selected_provider_id'] as String?)
            ?.trim();
    final baseUrl =
        (config.additionalConfig['llm.selected_base_url'] as String?)?.trim();
    final modelId = config.model.trim();
    if (providerId == null ||
        providerId.isEmpty ||
        baseUrl == null ||
        baseUrl.isEmpty ||
        modelId.isEmpty) {
      return null;
    }
    final rawStyle =
        (config.additionalConfig['llm.selected_api_style'] as String?)?.trim();
    return _CapabilityTarget(
      providerId: providerId,
      providerStyle: _readApiStyle(rawStyle) ??
          config.apiStyle ??
          ApiStyle.chatCompletions,
      baseUrlFingerprint: baseUrl,
      modelId: modelId,
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

class _CapabilityTarget {
  const _CapabilityTarget({
    required this.providerId,
    required this.providerStyle,
    required this.baseUrlFingerprint,
    required this.modelId,
  });

  final String providerId;
  final ApiStyle providerStyle;
  final String baseUrlFingerprint;
  final String modelId;
}
