import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionTokenBudgetService', () {
    test('signals compression when estimated input reaches pressure threshold',
        () {
      final service = SessionTokenBudgetService(
        modelBudgetResolver: (_) => const SessionModelBudget(
          maxContextTokens: 1000,
          reservedOutputTokens: 200,
          safetyMarginTokens: 100,
          pressureThreshold: 0.85,
        ),
      );

      final result = service.evaluate(
        modelName: 'test-model',
        systemPromptTokens: 120,
        toolSchemaTokens: 80,
        candidateContextTokens: 420,
        currentTurnTokens: 90,
      );

      expect(result.inputBudget, 700);
      expect(result.estimatedInputTokens, 710);
      expect(result.shouldCompress, true);
    });

    test('does not signal compression when pressure stays below threshold', () {
      final service = SessionTokenBudgetService(
        modelBudgetResolver: (_) => const SessionModelBudget(
          maxContextTokens: 1000,
          reservedOutputTokens: 200,
          safetyMarginTokens: 100,
          pressureThreshold: 0.9,
        ),
      );

      final result = service.evaluate(
        modelName: 'test-model',
        systemPromptTokens: 100,
        toolSchemaTokens: 60,
        candidateContextTokens: 200,
        currentTurnTokens: 80,
      );

      expect(result.estimatedInputTokens, 440);
      expect(result.shouldCompress, false);
      expect(result.pressureRatio, closeTo(440 / 700, 0.0001));
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
