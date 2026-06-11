import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionTokenBudgetService', () {
    test(
        'uses smaller provider input cap when deriving effective input budget',
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
