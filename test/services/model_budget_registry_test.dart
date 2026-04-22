import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelBudgetRegistry', () {
    test('resolves exact model profile before family fallback', () {
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

      final profile = registry.resolve('gpt-5');

      expect(profile.modelId, 'gpt-5');
      expect(profile.maxContextTokens, 200000);
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

      final profile = registry.resolve('gpt-5');

      expect(profile.modelId, 'gpt-5-runtime');
      expect(profile.maxContextTokens, 256000);
      expect(profile.compactionConfig.compressionTriggerRatio, 0.75);
    });

    test('falls back to conservative default profile when model is unknown',
        () {
      final registry = ModelBudgetRegistry();

      final profile = registry.resolve('unknown-model');

      expect(profile.maxContextTokens, greaterThan(0));
      expect(profile.reservedOutputTokens, greaterThan(0));
      expect(profile.compactionConfig.minRecentCompletedTurns, 1);
    });
  });
}
