import '../models/chat_message.dart';

class SessionModelBudget {
  final int maxContextTokens;
  final int reservedOutputTokens;
  final int safetyMarginTokens;
  final double pressureThreshold;

  const SessionModelBudget({
    required this.maxContextTokens,
    required this.reservedOutputTokens,
    required this.safetyMarginTokens,
    this.pressureThreshold = 0.85,
  });

  int get inputBudget =>
      maxContextTokens - reservedOutputTokens - safetyMarginTokens;
}

class SessionBudgetEvaluation {
  final int inputBudget;
  final int estimatedInputTokens;
  final double pressureRatio;
  final bool shouldCompress;

  const SessionBudgetEvaluation({
    required this.inputBudget,
    required this.estimatedInputTokens,
    required this.pressureRatio,
    required this.shouldCompress,
  });
}

typedef SessionModelBudgetResolver = SessionModelBudget Function(
    String modelName);

class SessionTokenBudgetService {
  SessionTokenBudgetService({
    SessionModelBudgetResolver? modelBudgetResolver,
  }) : _modelBudgetResolver = modelBudgetResolver ?? _defaultModelBudget;

  final SessionModelBudgetResolver _modelBudgetResolver;

  SessionModelBudget resolveBudget(String modelName) {
    return _modelBudgetResolver(modelName);
  }

  SessionBudgetEvaluation evaluate({
    required String modelName,
    required int systemPromptTokens,
    required int toolSchemaTokens,
    required int candidateContextTokens,
    required int currentTurnTokens,
  }) {
    final budget = resolveBudget(modelName);
    final inputBudget = budget.inputBudget;
    final estimatedInputTokens = systemPromptTokens +
        toolSchemaTokens +
        candidateContextTokens +
        currentTurnTokens;
    final pressureRatio =
        inputBudget <= 0 ? 1.0 : estimatedInputTokens / inputBudget;

    return SessionBudgetEvaluation(
      inputBudget: inputBudget,
      estimatedInputTokens: estimatedInputTokens,
      pressureRatio: pressureRatio,
      shouldCompress: pressureRatio >= budget.pressureThreshold,
    );
  }

  int estimateTextTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    return trimmed.runes.fold<int>(0, (total, rune) {
      return total + (rune > 127 ? 2 : 1);
    });
  }

  int estimateMessagesTokens(List<ChatMessage> messages) {
    return messages.fold<int>(
      0,
      (total, message) => total + estimateTextTokens(message.text),
    );
  }

  static SessionModelBudget _defaultModelBudget(String modelName) {
    final normalized = modelName.trim().toLowerCase();
    if (normalized.contains('gpt-4') || normalized.contains('claude')) {
      return const SessionModelBudget(
        maxContextTokens: 128000,
        reservedOutputTokens: 8000,
        safetyMarginTokens: 4000,
      );
    }
    if (normalized.contains('gpt-5')) {
      return const SessionModelBudget(
        maxContextTokens: 128000,
        reservedOutputTokens: 10000,
        safetyMarginTokens: 4000,
      );
    }
    return const SessionModelBudget(
      maxContextTokens: 32000,
      reservedOutputTokens: 4000,
      safetyMarginTokens: 2000,
    );
  }
}
