import '../models/chat_event.dart';
import '../models/session/context_usage_category.dart';
import '../models/session/context_usage_top_item.dart';
import '../models/session/context_window_segment.dart';
import '../models/session/context_window_snapshot.dart';
import '../models/tool/tool_result.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import 'chat_service.dart';
import 'session_context_service.dart';
import 'session_token_budget_service.dart';
import 'tool_result_context_projector.dart';

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
  static const ToolResultContextProjector _toolResultContextProjector =
      ToolResultContextProjector();

  Future<ContextWindowSnapshot?> buildLatestWindowSnapshotForGroup({
    required int groupId,
    required ChatConfig config,
  }) async {
    final turns = await _chatTurnRepository.getTurnsByGroup(groupId);
    if (turns.isEmpty) {
      return null;
    }
    final sortedTurns = [...turns]..sort((left, right) {
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
    final transcript =
        await _chatEventRepository.listEventsByTurn(latestTurnId);
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
    final resolvedBudget = state.resolvedBudget;
    final maxContextTokens = resolvedBudget.maxContextTokens;
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
    final reservedOutputTokens = resolvedBudget.reservedOutputTokens;
    final reasoningReserveTokens = resolvedBudget.reasoningReserveTokens;
    final safetyMarginTokens = resolvedBudget.safetyMarginTokens;
    final reserveTokens =
        reservedOutputTokens + reasoningReserveTokens + safetyMarginTokens;
    final freeHeadroomTokens = (maxContextTokens -
            state.budgetEvaluation.totalInputTokens -
            reservedOutputTokens -
            reasoningReserveTokens -
            safetyMarginTokens)
        .clamp(0, maxContextTokens);

    final filteredCurrentTurnTranscript = _filterTranscriptBySnapshot(
      snapshotCoveredUntilTurnId: state.activeSnapshot?.coveredUntilTurnId,
      snapshotCoveredUntilEventId: state.activeSnapshot?.coveredUntilEventId,
      currentTurnId: currentTurnId,
      transcript: currentTurnTranscript,
    );
    final recentEventsByTurn = await _loadEventsForTurnIds(
      groupId: groupId,
      turnIds: state.recentSegments.map((segment) => segment.turnId).toSet(),
    );
    final toolResultTokens = _sumToolResultTokens(
      events: [
        ...recentEventsByTurn.values.expand((events) => events),
        ...filteredCurrentTurnTranscript,
      ],
    );
    final systemSettingsTokens =
        state.systemPromptTokens + state.runtimeUserContextTokens;
    final conversationTokens = (state.budgetEvaluation.totalInputTokens -
            systemSettingsTokens -
            summaryTokens -
            toolResultTokens)
        .clamp(0, state.budgetEvaluation.totalInputTokens);
    final usedWindowTokens =
        state.budgetEvaluation.totalInputTokens + reserveTokens;
    final categories = _buildUsageCategories(
      maxContextTokens: maxContextTokens,
      recentConversationTokens: conversationTokens,
      toolResultTokens: toolResultTokens,
      historySummaryTokens: summaryTokens,
      systemSettingsTokens: systemSettingsTokens,
      reserveTokens: reserveTokens,
    );
    final topItems = _buildTopItems(
      maxContextTokens: maxContextTokens,
      events: [
        ...recentEventsByTurn.values.expand((events) => events),
        ...filteredCurrentTurnTranscript,
      ],
    );

    return ContextWindowSnapshot(
      modelName: state.modelName,
      maxContextTokens: maxContextTokens,
      effectiveInputBudget: state.budgetEvaluation.effectiveInputBudget,
      autoCompactTriggerTokens: state.budgetEvaluation.autoCompactTriggerTokens,
      totalEstimatedInputTokens: state.budgetEvaluation.totalInputTokens,
      plannerInputUsageRatio: state.budgetEvaluation.plannerInputUsageRatio,
      totalWindowUsageRatio: _ratio(
        numerator: state.budgetEvaluation.totalInputTokens,
        denominator: maxContextTokens,
      ),
      effectiveInputUsageRatio: state.budgetEvaluation.effectiveInputUsageRatio,
      usedWindowTokens: usedWindowTokens,
      usedWindowRatio: _ratio(
        numerator: usedWindowTokens,
        denominator: maxContextTokens,
      ),
      didCompactHistory: state.didCompactHistory,
      snapshotCoveredUntilTurnId: state.activeSnapshot?.coveredUntilTurnId,
      recentCompletedTurnCount: state.recentSegments.length,
      capabilitySource: state.budgetEvaluation.capabilitySource,
      segments: [
        if (state.systemPromptTokens > 0)
          _segment(
            type: ContextWindowSegmentType.systemPrompt,
            label: 'system prompt',
            tokens: state.systemPromptTokens,
            totalBudget: maxContextTokens,
            usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
            isPlannerVisible: true,
          ),
        if (state.runtimeUserContextTokens > 0)
          _segment(
            type: ContextWindowSegmentType.runtimeUserContext,
            label: 'runtime user context',
            tokens: state.runtimeUserContextTokens,
            totalBudget: maxContextTokens,
            usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
            isPlannerVisible: true,
          ),
        if (summaryTokens > 0)
          _segment(
            type: ContextWindowSegmentType.historySummary,
            label: 'history summary',
            tokens: summaryTokens,
            totalBudget: maxContextTokens,
            usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
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
            totalBudget: maxContextTokens,
            usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
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
            totalBudget: maxContextTokens,
            usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
            isPlannerVisible: true,
            details: {
              'messageCount': state.currentTurnMessages.length,
            },
          ),
        _segment(
          type: ContextWindowSegmentType.reservedOutput,
          label: 'reserved output',
          tokens: reservedOutputTokens,
          totalBudget: maxContextTokens,
          usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
          isPlannerVisible: false,
        ),
        _segment(
          type: ContextWindowSegmentType.reasoningReserve,
          label: 'reasoning reserve',
          tokens: reasoningReserveTokens,
          totalBudget: maxContextTokens,
          usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
          isPlannerVisible: false,
        ),
        _segment(
          type: ContextWindowSegmentType.safetyMargin,
          label: 'safety margin',
          tokens: safetyMarginTokens,
          totalBudget: maxContextTokens,
          usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
          isPlannerVisible: false,
        ),
        _segment(
          type: ContextWindowSegmentType.freeHeadroom,
          label: 'free headroom',
          tokens: freeHeadroomTokens,
          totalBudget: maxContextTokens,
          usableInputBudget: state.budgetEvaluation.effectiveInputBudget,
          isPlannerVisible: false,
        ),
      ],
      categories: categories,
      topItems: topItems,
    );
  }

  Future<Map<int, List<ChatEvent>>> _loadEventsForTurnIds({
    required int groupId,
    required Set<int> turnIds,
  }) async {
    if (turnIds.isEmpty) {
      return const {};
    }
    final events = await _chatEventRepository.listEventsByGroup(groupId);
    final grouped = <int, List<ChatEvent>>{};
    for (final event in events) {
      if (!turnIds.contains(event.turnId)) {
        continue;
      }
      grouped.putIfAbsent(event.turnId, () => <ChatEvent>[]).add(event);
    }
    return grouped;
  }

  List<ChatEvent> _filterTranscriptBySnapshot({
    required int? snapshotCoveredUntilTurnId,
    required int? snapshotCoveredUntilEventId,
    required int currentTurnId,
    required List<ChatEvent> transcript,
  }) {
    if (snapshotCoveredUntilTurnId != currentTurnId ||
        snapshotCoveredUntilEventId == null) {
      return transcript;
    }
    return transcript
        .where((event) =>
            (event.id ?? event.sequence) > snapshotCoveredUntilEventId)
        .toList(growable: false);
  }

  List<ContextUsageCategory> _buildUsageCategories({
    required int maxContextTokens,
    required int recentConversationTokens,
    required int toolResultTokens,
    required int historySummaryTokens,
    required int systemSettingsTokens,
    required int reserveTokens,
  }) {
    final categories = <ContextUsageCategory>[
      if (recentConversationTokens > 0)
        _usageCategory(
          type: ContextUsageCategoryType.recentConversation,
          label: '最近对话',
          tokens: recentConversationTokens,
          maxContextTokens: maxContextTokens,
        ),
      if (toolResultTokens > 0)
        _usageCategory(
          type: ContextUsageCategoryType.toolResults,
          label: '工具 / 网页 / 文件结果',
          tokens: toolResultTokens,
          maxContextTokens: maxContextTokens,
        ),
      if (historySummaryTokens > 0)
        _usageCategory(
          type: ContextUsageCategoryType.historySummary,
          label: '历史摘要',
          tokens: historySummaryTokens,
          maxContextTokens: maxContextTokens,
        ),
      if (systemSettingsTokens > 0)
        _usageCategory(
          type: ContextUsageCategoryType.systemSettings,
          label: '系统设定',
          tokens: systemSettingsTokens,
          maxContextTokens: maxContextTokens,
        ),
    ]..sort(
        (left, right) => right.estimatedTokens.compareTo(left.estimatedTokens));

    if (reserveTokens > 0) {
      categories.add(
        _usageCategory(
          type: ContextUsageCategoryType.reserve,
          label: '预留',
          tokens: reserveTokens,
          maxContextTokens: maxContextTokens,
        ),
      );
    }
    return categories.toList(growable: false);
  }

  ContextUsageCategory _usageCategory({
    required ContextUsageCategoryType type,
    required String label,
    required int tokens,
    required int maxContextTokens,
    Map<String, Object?> details = const {},
  }) {
    return ContextUsageCategory(
      type: type,
      label: label,
      estimatedTokens: tokens,
      shareOfTotalWindow: _ratio(
        numerator: tokens,
        denominator: maxContextTokens,
      ),
      details: details,
    );
  }

  int _sumToolResultTokens({
    required List<ChatEvent> events,
  }) {
    return events.fold<int>(
      0,
      (total, event) => total + _toolEventTokens(event),
    );
  }

  List<ContextUsageTopItem> _buildTopItems({
    required int maxContextTokens,
    required List<ChatEvent> events,
  }) {
    final items = events
        .map((event) => _topItemFromEvent(
              event: event,
              maxContextTokens: maxContextTokens,
            ))
        .whereType<ContextUsageTopItem>()
        .toList(growable: false)
      ..sort((left, right) =>
          right.estimatedTokens.compareTo(left.estimatedTokens));
    if (items.length <= 5) {
      return items;
    }
    return items.take(5).toList(growable: false);
  }

  ContextUsageTopItem? _topItemFromEvent({
    required ChatEvent event,
    required int maxContextTokens,
  }) {
    if (event.eventType != ChatEventType.toolResult &&
        event.eventType != ChatEventType.toolError) {
      return null;
    }
    final payload = event.payloadJson;
    if (payload == null) {
      return null;
    }
    final result = ToolResult.fromJson(payload);
    final projectedText =
        _toolResultContextProjector.projectToContextText(result)?.trim();
    final content = (projectedText == null || projectedText.isEmpty)
        ? (event.content?.trim() ?? '')
        : projectedText;
    if (content.isEmpty) {
      return null;
    }
    final estimatedTokens = _tokenBudgetService.estimateTextTokens(content);
    if (estimatedTokens <= 0) {
      return null;
    }
    return ContextUsageTopItem(
      toolName:
          result.toolName.trim().isEmpty ? 'tool' : result.toolName.trim(),
      objectLabel: _resolveTopItemObjectLabel(result),
      estimatedTokens: estimatedTokens,
      shareOfTotalWindow: _ratio(
        numerator: estimatedTokens,
        denominator: maxContextTokens,
      ),
      details: {
        'turnId': event.turnId,
        'eventId': event.id,
      },
    );
  }

  int _toolEventTokens(ChatEvent event) {
    if (event.eventType != ChatEventType.toolResult &&
        event.eventType != ChatEventType.toolError) {
      return 0;
    }
    final payload = event.payloadJson;
    if (payload == null) {
      return 0;
    }
    final result = ToolResult.fromJson(payload);
    final projectedText =
        _toolResultContextProjector.projectToContextText(result)?.trim();
    final content = (projectedText == null || projectedText.isEmpty)
        ? (event.content?.trim() ?? '')
        : projectedText;
    if (content.isEmpty) {
      return 0;
    }
    return _tokenBudgetService.estimateTextTokens(content);
  }

  String _resolveTopItemObjectLabel(ToolResult result) {
    final data = result.data;
    final toolName = result.toolName.trim();
    switch (toolName) {
      case 'web_search':
        return _firstNonEmpty([
              data['query'],
              data['title'],
              data['url'],
            ]) ??
            'search result';
      case 'fetch_webpage':
        return _firstNonEmpty([
              data['url'],
              data['title'],
            ]) ??
            'webpage result';
      case 'Read':
      case 'Write':
      case 'Edit':
      case 'Delete':
      case 'create_artifact':
        return _firstNonEmpty([
              data['filePath'],
              data['path'],
              data['sourcePath'],
              data['title'],
            ]) ??
            'file result';
      case 'LS':
      case 'Glob':
      case 'Grep':
        return _firstNonEmpty([
              data['path'],
              data['pattern'],
              data['title'],
            ]) ??
            'workspace result';
      default:
        return _firstNonEmpty([
              data['title'],
              data['name'],
              data['url'],
              data['path'],
              data['message'],
              data['id'],
            ]) ??
            'result';
    }
  }

  String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
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
