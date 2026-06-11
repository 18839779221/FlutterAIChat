import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/llm/model_capability_override.dart';
import 'package:ai_chat/models/llm/model_capability_source_kind.dart';
import 'package:ai_chat/models/llm/resolved_model_capability.dart';
import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/model_capability_sources/provider_model_capability_source.dart';
import 'package:ai_chat/services/model_capability_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prefers local override over fallback capability and policy', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'openai',
        defaultModelId: 'gpt-5',
        providers: [
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'k',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-5',
                name: 'GPT-5',
                capabilityOverride: ModelCapabilityOverride(
                  contextWindowTotal: 1000000,
                  maxInputTokens: 256000,
                  maxOutputTokens: 32000,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final resolver = ModelCapabilityResolver(
      settingsRepository: repository,
      budgetRegistry: ModelBudgetRegistry(
        profiles: {
          'gpt-5': const ModelBudgetProfile(
            modelId: 'gpt-5',
            maxContextTokens: 128000,
            reservedOutputTokens: 12000,
            reasoningReserveTokens: 8000,
            safetyMarginTokens: 4000,
            compactionConfig: ContextCompactionConfig(),
          ),
        },
      ),
      providerSources: const [],
      catalogSource: null,
    );

    final budget = await resolver.resolveForRuntime(
      const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        apiStyle: ApiStyle.responses,
        additionalConfig: {
          'llm.selected_provider_id': 'openai',
          'llm.selected_model_id': 'gpt-5',
          'llm.selected_base_url': 'https://api.openai.com/v1',
        },
      ),
    );

    expect(budget.capability.source, ModelCapabilitySourceKind.localOverride);
    expect(budget.capability.contextWindowTotal, 1000000);
    expect(budget.plannerMaxOutputTokens, 12000);
  });

  test('uses provider metadata when local override is absent', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'anthropic',
        defaultModelId: 'claude-sonnet-4-5',
        providers: [
          LlmProviderConfig(
            id: 'anthropic',
            name: 'Anthropic',
            apiKey: 'k',
            baseUrl: 'https://api.anthropic.com/v1/messages',
            models: [
              LlmProviderModel(
                id: 'claude-sonnet-4-5',
                name: 'Claude Sonnet 4.5',
              ),
            ],
          ),
        ],
      ),
    );
    final resolver = ModelCapabilityResolver(
      settingsRepository: repository,
      budgetRegistry: ModelBudgetRegistry(),
      providerSources: [
        _StaticCapabilitySource(
          const ResolvedModelCapability(
            providerId: 'anthropic',
            providerStyle: ApiStyle.anthropicMessages,
            baseUrlFingerprint: 'https://api.anthropic.com/v1/messages',
            modelId: 'claude-sonnet-4-5',
            contextWindowTotal: 200000,
            maxInputTokens: 200000,
            maxOutputTokens: 32000,
            source: ModelCapabilitySourceKind.providerMetadata,
          ),
        ),
      ],
      catalogSource: null,
    );

    final budget = await resolver.resolveForRuntime(
      const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        model: 'claude-sonnet-4-5',
        apiStyle: ApiStyle.anthropicMessages,
        additionalConfig: {
          'llm.selected_provider_id': 'anthropic',
          'llm.selected_model_id': 'claude-sonnet-4-5',
          'llm.selected_api_style': 'anthropicMessages',
          'llm.selected_base_url': 'https://api.anthropic.com/v1/messages',
        },
      ),
    );

    expect(
        budget.capability.source, ModelCapabilitySourceKind.providerMetadata);
    expect(budget.capability.maxOutputTokens, 32000);
  });

  test('uses catalog when provider metadata is unavailable', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'openai',
        defaultModelId: 'gpt-5',
        providers: [
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'k',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-5',
                name: 'GPT-5',
              ),
            ],
          ),
        ],
      ),
    );
    final resolver = ModelCapabilityResolver(
      settingsRepository: repository,
      budgetRegistry: ModelBudgetRegistry(),
      providerSources: const [_StaticCapabilitySource(null)],
      catalogSource: const _StaticCapabilitySource(
        ResolvedModelCapability(
          providerId: 'openai',
          providerStyle: ApiStyle.responses,
          baseUrlFingerprint: 'https://api.openai.com/v1',
          modelId: 'gpt-5',
          contextWindowTotal: 1000000,
          maxInputTokens: 256000,
          maxOutputTokens: 32000,
          source: ModelCapabilitySourceKind.catalog,
        ),
      ),
    );

    final budget = await resolver.resolveForRuntime(
      const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        apiStyle: ApiStyle.responses,
        additionalConfig: {
          'llm.selected_provider_id': 'openai',
          'llm.selected_model_id': 'gpt-5',
          'llm.selected_api_style': 'responses',
          'llm.selected_base_url': 'https://api.openai.com/v1',
        },
      ),
    );

    expect(budget.capability.source, ModelCapabilitySourceKind.catalog);
    expect(budget.capability.contextWindowTotal, 1000000);
  });

  test(
      'reads cached capability on sync path and preserves it on refresh failure',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'openai',
        defaultModelId: 'gpt-5',
        providers: [
          LlmProviderConfig(
            id: 'openai',
            name: 'OpenAI',
            apiKey: 'k',
            baseUrl: 'https://api.openai.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-5',
                name: 'GPT-5',
              ),
            ],
          ),
        ],
      ),
    );
    await repository.saveModelCapabilityCache(
      const ResolvedModelCapability(
        providerId: 'openai',
        providerStyle: ApiStyle.responses,
        baseUrlFingerprint: 'https://api.openai.com/v1',
        modelId: 'gpt-5',
        contextWindowTotal: 1000000,
        maxInputTokens: 256000,
        maxOutputTokens: 32000,
        source: ModelCapabilitySourceKind.catalog,
      ),
    );
    final resolver = ModelCapabilityResolver(
      settingsRepository: repository,
      budgetRegistry: ModelBudgetRegistry(),
      providerSources: const [_ThrowingCapabilitySource()],
      catalogSource: const _ThrowingCapabilitySource(),
    );
    const config = LLMConfig(
      apiKey: 'k',
      apiUrl: 'https://api.openai.com/v1',
      model: 'gpt-5',
      apiStyle: ApiStyle.responses,
      additionalConfig: {
        'llm.selected_provider_id': 'openai',
        'llm.selected_model_id': 'gpt-5',
        'llm.selected_api_style': 'responses',
        'llm.selected_base_url': 'https://api.openai.com/v1',
      },
    );

    final cachedBudget = resolver.resolveCachedOrFallback(config);
    await resolver.refreshInBackground(config);
    final cachedAfterRefresh = await repository.getModelCapabilityCache(
      providerId: 'openai',
      providerStyle: ApiStyle.responses,
      baseUrlFingerprint: 'https://api.openai.com/v1',
      modelId: 'gpt-5',
    );

    expect(cachedBudget.capability.source, ModelCapabilitySourceKind.catalog);
    expect(cachedBudget.capability.contextWindowTotal, 1000000);
    expect(cachedAfterRefresh?.contextWindowTotal, 1000000);
    expect(cachedAfterRefresh?.source, ModelCapabilitySourceKind.catalog);
  });
}

class _StaticCapabilitySource implements ProviderModelCapabilitySource {
  const _StaticCapabilitySource(this.capability);

  final ResolvedModelCapability? capability;

  @override
  bool supports(LLMConfig config) => true;

  @override
  Future<ResolvedModelCapability?> fetch(LLMConfig config) async => capability;
}

class _ThrowingCapabilitySource implements ProviderModelCapabilitySource {
  const _ThrowingCapabilitySource();

  @override
  bool supports(LLMConfig config) => true;

  @override
  Future<ResolvedModelCapability?> fetch(LLMConfig config) async {
    throw Exception('boom');
  }
}
