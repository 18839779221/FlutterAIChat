import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/model_capability_source_kind.dart';
import 'package:ai_chat/models/llm/resolved_model_capability.dart';
import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/model_capability_resolver.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SessionTokenBudgetService', () {
    test('derives planner budget from resolved model capability and policy',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repository = AppSettingsRepository(
        await SharedPreferences.getInstance(),
        localDefaultsLoader: () async => null,
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
      final service = SessionTokenBudgetService(
        modelCapabilityResolver: ModelCapabilityResolver(
          settingsRepository: repository,
          budgetRegistry: ModelBudgetRegistry(
            profiles: {
              'gpt-5': const ModelBudgetProfile(
                modelId: 'gpt-5-policy',
                maxContextTokens: 0,
                reservedOutputTokens: 12000,
                reasoningReserveTokens: 8000,
                safetyMarginTokens: 4000,
                compactionConfig: ContextCompactionConfig(
                  autoCompactBufferTokens: 4000,
                ),
              ),
            },
          ),
        ),
      );

      final result = service.evaluatePlannerBudget(
        runtimeConfig: const LLMConfig(
          apiKey: 'k',
          apiUrl: 'https://api.openai.com/v1',
          model: 'gpt-5',
          apiStyle: ApiStyle.responses,
          additionalConfig: {
            'llm.selected_provider_id': 'openai',
            'llm.selected_api_style': 'responses',
            'llm.selected_base_url': 'https://api.openai.com/v1',
          },
        ),
        fixedPrefixTokens: 2000,
        summaryTokens: 1000,
        recentTurnsTokens: 4000,
        currentTurnTokens: 3000,
        toolSchemaTokens: 2000,
      );

      expect(result.effectiveInputBudget, 256000);
      expect(result.maxContextTokens, 1000000);
      expect(result.capabilitySource, ModelCapabilitySourceKind.catalog);
    });

    test('uses smaller provider input cap when deriving effective input budget',
        () {
      final service = SessionTokenBudgetService(
        modelBudgetRegistry: ModelBudgetRegistry(
          profiles: {
            'test-model': const ModelBudgetProfile(
              modelId: 'test-model',
              maxContextTokens: 1000,
              providerInputCap: 700,
              reservedOutputTokens: 100,
              reasoningReserveTokens: 50,
              safetyMarginTokens: 50,
              compactionConfig: ContextCompactionConfig(
                autoCompactBufferTokens: 80,
              ),
            ),
          },
        ),
      );

      final result = service.evaluatePlannerBudget(
        modelName: 'test-model',
        fixedPrefixTokens: 200,
        summaryTokens: 100,
        recentTurnsTokens: 60,
        currentTurnTokens: 40,
        toolSchemaTokens: 20,
      );

      expect(result.effectiveInputBudget, 700);
      expect(result.autoCompactTriggerTokens, 620);
      expect(result.fixedPrefixTokens, 200);
      expect(result.toolSchemaTokens, 20);
      expect(result.historyPayloadTokens, 160);
      expect(result.totalInputTokens, 420);
      expect(result.shouldCompact, isFalse);
    });

    test('signals compression when estimated input reaches pressure threshold',
        () {
      final service = SessionTokenBudgetService(
        modelBudgetRegistry: ModelBudgetRegistry(
          profiles: {
            'test-model': const ModelBudgetProfile(
              modelId: 'test-model',
              maxContextTokens: 1000,
              reservedOutputTokens: 200,
              reasoningReserveTokens: 100,
              safetyMarginTokens: 100,
              compactionConfig: ContextCompactionConfig(
                autoCompactBufferTokens: 120,
              ),
            ),
          },
        ),
      );

      final result = service.evaluatePlannerBudget(
        modelName: 'test-model',
        fixedPrefixTokens: 300,
        summaryTokens: 140,
        recentTurnsTokens: 90,
        currentTurnTokens: 80,
        toolSchemaTokens: 10,
      );

      expect(result.totalInputTokens, 620);
      expect(result.shouldCompact, true);
      expect(result.autoCompactTriggerTokens, 480);
      expect(result.plannerInputUsageRatio, closeTo(620 / 480, 0.0001));
    });

    test('estimates message tokens from mixed ascii and non-ascii text', () {
      final service = SessionTokenBudgetService();
      final tokens = service.estimateMessagesTokens([
        ChatMessage(text: 'abc', role: MessageRole.user),
        ChatMessage(text: '你好', role: MessageRole.assistant),
      ]);

      expect(tokens, 7);
    });
  });
}
