import '../models/chat_event.dart';
import '../models/session/context_window_segment.dart';
import '../models/session/context_window_snapshot.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import 'chat_service.dart';
import 'session_context_service.dart';
import 'session_token_budget_service.dart';

class SessionContextInspectorService {
  SessionContextInspectorService({
    required SessionContextService sessionContextService,
    required SessionTokenBudgetService tokenBudgetService,
    required ChatTurnRepository chatTurnRepository,
    required ChatEventRepository chatEventRepository,
  })  : _sessionContextService = sessionContextService,
        _tokenBudgetService = tokenBudgetService,
        _chatTurnRepository = chatTurnRepository,
        _chatEventRepository = chatEventRepository;

  final SessionContextService _sessionContextService;
  final SessionTokenBudgetService _tokenBudgetService;
  final ChatTurnRepository _chatTurnRepository;
  final ChatEventRepository _chatEventRepository;

  Future<ContextWindowSnapshot?> buildLatestWindowSnapshotForGroup({
    required int groupId,
    required ChatConfig config,
  }) async {
    final turns = await _chatTurnRepository.getTurnsByGroup(groupId);
    if (turns.isEmpty) {
      return null;
    }
    final sortedTurns = [...turns]
      ..sort((left, right) {
        final leftId = left.id ?? 0;
        final rightId = right.id ?? 0;
        return leftId.compareTo(rightId);
      });
    final latestTurn = sortedTurns.lastWhere(
      (turn) => turn.id != null,
      orElse: () => sortedTurns.last,
    );
    final latestTurnId = latestTurn.id;
    if (latestTurnId == null) {
      return null;
    }
    final transcript = await _chatEventRepository.listEventsByTurn(latestTurnId);
    return buildLatestWindowSnapshot(
      groupId: groupId,
      currentTurnId: latestTurnId,
      currentTurnTranscript: transcript,
      config: config,
    );
  }

  Future<ContextWindowSnapshot> buildLatestWindowSnapshot({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    final state = await _sessionContextService.buildPlannerContextState(
      groupId: groupId,
      currentTurnId: currentTurnId,
      currentTurnTranscript: currentTurnTranscript,
      config: config,
    );
    final profile = _tokenBudgetService.resolveProfile(state.modelName);
    final summaryTokens = state.activeSnapshot == null
        ? 0
        : state.activeSnapshot!.estimatedTokens > 0
            ? state.activeSnapshot!.estimatedTokens
            : _tokenBudgetService.estimateTextTokens(
                state.activeSnapshot!.summaryText,
              );
    final recentTokens = state.recentSegments.fold<int>(
      0,
      (total, segment) => total + segment.estimatedTokens,
    );
    final currentTurnTokens = _tokenBudgetService.estimateMessagesTokens(
      state.currentTurnMessages,
    );
    final reservedOutputTokens = profile.reservedOutputTokens;
    final reasoningReserveTokens = profile.reasoningReserveTokens;
    final safetyMarginTokens = profile.safetyMarginTokens;
    final freeHeadroomTokens =
        (profile.maxContextTokens -
                state.budgetEvaluation.totalInputTokens -
                reservedOutputTokens -
                reasoningReserveTokens -
                safetyMarginTokens)
            .clamp(0, profile.maxContextTokens);

    return ContextWindowSnapshot(
      modelName: state.modelName,
      maxContextTokens: profile.maxContextTokens,
      usableInputBudget: profile.usableInputBudget,
      compressionTriggerRatio: profile.compactionConfig.compressionTriggerRatio,
      totalEstimatedInputTokens: state.budgetEvaluation.totalInputTokens,
      totalWindowUsageRatio: _ratio(
        numerator: state.budgetEvaluation.totalInputTokens,
        denominator: profile.maxContextTokens,
      ),
      usableInputUsageRatio: _ratio(
        numerator: state.budgetEvaluation.totalInputTokens,
        denominator: profile.usableInputBudget,
      ),
      didCompactHistory: state.didCompactHistory,
      snapshotCoveredUntilTurnId: state.activeSnapshot?.coveredUntilTurnId,
      recentCompletedTurnCount: state.recentSegments.length,
      segments: [
        if (state.systemPromptTokens > 0)
          _segment(
            type: ContextWindowSegmentType.systemPrompt,
            label: 'system prompt',
            tokens: state.systemPromptTokens,
            totalBudget: profile.maxContextTokens,
            usableInputBudget: profile.usableInputBudget,
            isPlannerVisible: true,
          ),
        if (state.runtimeUserContextTokens > 0)
          _segment(
            type: ContextWindowSegmentType.runtimeUserContext,
            label: 'runtime user context',
            tokens: state.runtimeUserContextTokens,
            totalBudget: profile.maxContextTokens,
            usableInputBudget: profile.usableInputBudget,
            isPlannerVisible: true,
          ),
        if (summaryTokens > 0)
          _segment(
            type: ContextWindowSegmentType.historySummary,
            label: 'history summary',
            tokens: summaryTokens,
            totalBudget: profile.maxContextTokens,
            usableInputBudget: profile.usableInputBudget,
            isPlannerVisible: true,
            details: {
              'coveredUntilTurnId': state.activeSnapshot?.coveredUntilTurnId,
            },
          ),
        if (recentTokens > 0)
          _segment(
            type: ContextWindowSegmentType.recentCompletedTurns,
            label: 'recent completed turns',
            tokens: recentTokens,
            totalBudget: profile.maxContextTokens,
            usableInputBudget: profile.usableInputBudget,
            isPlannerVisible: true,
            details: {
              'turnCount': state.recentSegments.length,
            },
          ),
        if (currentTurnTokens > 0)
          _segment(
            type: ContextWindowSegmentType.currentTurnTranscript,
            label: 'current turn transcript',
            tokens: currentTurnTokens,
            totalBudget: profile.maxContextTokens,
            usableInputBudget: profile.usableInputBudget,
            isPlannerVisible: true,
            details: {
              'messageCount': state.currentTurnMessages.length,
            },
          ),
        _segment(
          type: ContextWindowSegmentType.reservedOutput,
          label: 'reserved output',
          tokens: reservedOutputTokens,
          totalBudget: profile.maxContextTokens,
          usableInputBudget: profile.usableInputBudget,
          isPlannerVisible: false,
        ),
        _segment(
          type: ContextWindowSegmentType.reasoningReserve,
          label: 'reasoning reserve',
          tokens: reasoningReserveTokens,
          totalBudget: profile.maxContextTokens,
          usableInputBudget: profile.usableInputBudget,
          isPlannerVisible: false,
        ),
        _segment(
          type: ContextWindowSegmentType.safetyMargin,
          label: 'safety margin',
          tokens: safetyMarginTokens,
          totalBudget: profile.maxContextTokens,
          usableInputBudget: profile.usableInputBudget,
          isPlannerVisible: false,
        ),
        _segment(
          type: ContextWindowSegmentType.freeHeadroom,
          label: 'free headroom',
          tokens: freeHeadroomTokens,
          totalBudget: profile.maxContextTokens,
          usableInputBudget: profile.usableInputBudget,
          isPlannerVisible: false,
        ),
      ],
    );
  }

  ContextWindowSegment _segment({
    required ContextWindowSegmentType type,
    required String label,
    required int tokens,
    required int totalBudget,
    required int usableInputBudget,
    required bool isPlannerVisible,
    Map<String, Object?> details = const {},
  }) {
    return ContextWindowSegment(
      type: type,
      label: label,
      estimatedTokens: tokens,
      shareOfTotalWindow: _ratio(
        numerator: tokens,
        denominator: totalBudget,
      ),
      shareOfUsableInput: _ratio(
        numerator: tokens,
        denominator: usableInputBudget,
      ),
      isPlannerVisible: isPlannerVisible,
      details: details,
    );
  }

  double _ratio({
    required int numerator,
    required int denominator,
  }) {
    if (denominator <= 0) {
      return 0;
    }
    return numerator / denominator;
  }
}
