import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/llm/model_capability_override.dart';
import 'package:ai_chat/models/llm/model_capability_source_kind.dart';
import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
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
}
