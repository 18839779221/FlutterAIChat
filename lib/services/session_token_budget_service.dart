import '../models/chat_message.dart';
import '../models/context/planner_context_carrier.dart';
import '../models/session/context_compaction_config.dart';
import '../models/session/model_budget_profile.dart';
import 'model_budget_registry.dart';

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

class SessionPlannerBudgetEvaluation {
  final int usableInputBudget;
  final int fixedPrefixTokens;
  final int summaryTokens;
  final int recentTurnsTokens;
  final int currentTurnTokens;
  final int historyPayloadTokens;
  final int totalInputTokens;
  final double totalUsageRatio;
  final bool shouldCompact;

  const SessionPlannerBudgetEvaluation({
    required this.usableInputBudget,
    required this.fixedPrefixTokens,
    required this.summaryTokens,
    required this.recentTurnsTokens,
    required this.currentTurnTokens,
    required this.historyPayloadTokens,
    required this.totalInputTokens,
    required this.totalUsageRatio,
    required this.shouldCompact,
  });
}

class SessionTokenBudgetService {
  SessionTokenBudgetService({
    SessionModelBudgetResolver? modelBudgetResolver,
    ModelBudgetRegistry? modelBudgetRegistry,
  })  : _modelBudgetResolver = modelBudgetResolver,
        _modelBudgetRegistry = modelBudgetRegistry ?? ModelBudgetRegistry();

  final SessionModelBudgetResolver? _modelBudgetResolver;
  final ModelBudgetRegistry _modelBudgetRegistry;

  SessionModelBudget resolveBudget(String modelName) {
    final resolver = _modelBudgetResolver;
    if (resolver != null) {
      return resolver(modelName);
    }
    final profile = resolveProfile(modelName);
    return SessionModelBudget(
      maxContextTokens: profile.maxContextTokens,
      reservedOutputTokens: profile.reservedOutputTokens,
      safetyMarginTokens: profile.safetyMarginTokens,
      pressureThreshold: profile.compactionConfig.compressionTriggerRatio,
    );
  }

  ModelBudgetProfile resolveProfile(String modelName) {
    final resolver = _modelBudgetResolver;
    if (resolver != null) {
      final budget = resolver(modelName);
      return ModelBudgetProfile(
        modelId: modelName.trim().isEmpty ? 'runtime' : modelName.trim(),
        maxContextTokens: budget.maxContextTokens,
        reservedOutputTokens: budget.reservedOutputTokens,
        reasoningReserveTokens: 0,
        safetyMarginTokens: budget.safetyMarginTokens,
        compactionConfig: ContextCompactionConfig(
          compressionTriggerRatio: budget.pressureThreshold,
        ),
      );
    }
    return _modelBudgetRegistry.resolve(modelName);
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

  SessionPlannerBudgetEvaluation evaluatePlannerBudget({
    required String modelName,
    required int fixedPrefixTokens,
    required int summaryTokens,
    required int recentTurnsTokens,
    required int currentTurnTokens,
  }) {
    final profile = resolveProfile(modelName);
    final usableInputBudget = profile.usableInputBudget;
    final historyPayloadTokens = summaryTokens + recentTurnsTokens;
    final totalInputTokens =
        fixedPrefixTokens + historyPayloadTokens + currentTurnTokens;
    final totalUsageRatio =
        usableInputBudget <= 0 ? 1.0 : totalInputTokens / usableInputBudget;

    return SessionPlannerBudgetEvaluation(
      usableInputBudget: usableInputBudget,
      fixedPrefixTokens: fixedPrefixTokens,
      summaryTokens: summaryTokens,
      recentTurnsTokens: recentTurnsTokens,
      currentTurnTokens: currentTurnTokens,
      historyPayloadTokens: historyPayloadTokens,
      totalInputTokens: totalInputTokens,
      totalUsageRatio: totalUsageRatio,
      shouldCompact:
          totalUsageRatio >= profile.compactionConfig.compressionTriggerRatio,
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

  int estimateCarriersTokens(List<PlannerContextCarrier> carriers) {
    return carriers.fold<int>(0, (total, c) => total + c.estimatedTokens);
  }
}
