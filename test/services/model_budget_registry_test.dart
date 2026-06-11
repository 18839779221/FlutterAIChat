import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelBudgetRegistry', () {
    test('resolves exact policy profile before family fallback', () {
      final registry = ModelBudgetRegistry(
        profiles: {
          'gpt-5': const ModelBudgetProfile(
            modelId: 'gpt-5',
            maxContextTokens: 200000,
            reservedOutputTokens: 16000,
            reasoningReserveTokens: 8000,
            safetyMarginTokens: 4000,
            compactionConfig: ContextCompactionConfig(),
          ),
        },
        familyProfiles: {
          'gpt': const ModelBudgetProfile(
            modelId: 'gpt-family',
            maxContextTokens: 128000,
            reservedOutputTokens: 12000,
            reasoningReserveTokens: 8000,
            safetyMarginTokens: 4000,
            compactionConfig: ContextCompactionConfig(),
          ),
        },
      );

      final profile = registry.resolvePolicy('gpt-5');

      expect(profile.modelId, 'gpt-5');
      expect(profile.reservedOutputTokens, 16000);
    });

    test('resolves fallback capability facts for exact models', () {
      final registry = ModelBudgetRegistry(
        profiles: {
          'gpt-5': const ModelBudgetProfile(
            modelId: 'gpt-5',
            maxContextTokens: 200000,
            providerInputCap: 180000,
            reservedOutputTokens: 16000,
            reasoningReserveTokens: 8000,
            safetyMarginTokens: 4000,
            compactionConfig: ContextCompactionConfig(),
          ),
        },
      );

      final capability = registry.resolveFallbackCapability('gpt-5');

      expect(capability.modelId, 'gpt-5');
      expect(capability.contextWindowTotal, 200000);
      expect(capability.maxInputTokens, 180000);
    });

    test('prefers runtime override over built-in defaults', () {
      final registry = ModelBudgetRegistry(
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
        runtimeOverrides: {
          'gpt-5': const ModelBudgetProfile(
            modelId: 'gpt-5-runtime',
            maxContextTokens: 256000,
            reservedOutputTokens: 20000,
            reasoningReserveTokens: 12000,
            safetyMarginTokens: 6000,
            compactionConfig: ContextCompactionConfig(
              compressionTriggerRatio: 0.75,
            ),
          ),
        },
      );

      final profile = registry.resolvePolicy('gpt-5');

      expect(profile.modelId, 'gpt-5-runtime');
      expect(profile.reservedOutputTokens, 20000);
      expect(profile.compactionConfig.compressionTriggerRatio, 0.75);
    });

    test('falls back to conservative default profile when model is unknown',
        () {
      final registry = ModelBudgetRegistry();

      final profile = registry.resolvePolicy('unknown-model');
      final capability = registry.resolveFallbackCapability('unknown-model');

      expect(capability.contextWindowTotal, greaterThan(0));
      expect(profile.reservedOutputTokens, greaterThan(0));
      expect(profile.compactionConfig.minRecentCompletedTurns, 1);
    });
  });
}
