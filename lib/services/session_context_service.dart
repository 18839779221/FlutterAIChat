import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/context/model_context_item.dart';
import '../models/session/context_compaction_config.dart';
import '../models/session/session_context_snapshot.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../repositories/session_context_snapshot_repository.dart';
import '../utils/logger.dart';
import 'chat_service.dart';
import 'prompt/runtime_user_context_service.dart';
import 'prompt/user_context_message_builder.dart';
import 'session_runtime_marker_service.dart';
import 'session_context_projector.dart';
import 'session_summary_service.dart';
import 'session_token_budget_service.dart';

class SessionContextTurnSegment {
  final int turnId;
  final List<ChatMessage> messages;
  final int estimatedTokens;

  const SessionContextTurnSegment({
    required this.turnId,
    required this.messages,
    required this.estimatedTokens,
  });
}

class SessionContextBuildResult {
  final String modelName;
  final String resolvedSystemPrompt;
  final int systemPromptTokens;
  final ChatMessage runtimeUserContextMessage;
  final int runtimeUserContextTokens;
  final SessionContextSnapshot? activeSnapshot;
  final List<SessionContextTurnSegment> recentSegments;
  final List<ChatMessage> currentTurnMessages;
  final SessionPlannerBudgetEvaluation budgetEvaluation;
  final bool didCompactHistory;

  const SessionContextBuildResult({
    required this.modelName,
    required this.resolvedSystemPrompt,
    required this.systemPromptTokens,
    required this.runtimeUserContextMessage,
    required this.runtimeUserContextTokens,
    required this.activeSnapshot,
    required this.recentSegments,
    required this.currentTurnMessages,
    required this.budgetEvaluation,
    required this.didCompactHistory,
  });

  List<ChatMessage> get plannerMessages => [
        runtimeUserContextMessage,
        if (activeSnapshot != null)
          ChatMessage(
            text: activeSnapshot!.summaryText,
            role: MessageRole.system,
            timestamp: activeSnapshot!.updatedAt,
            status: MessageStatus.completed,
          ),
        ...recentSegments.expand((segment) => segment.messages),
        ...currentTurnMessages,
      ];
}

class SessionContextService {
  static const String _tag = 'SessionContextService';

  SessionContextService({
    required ChatTurnRepository chatTurnRepository,
    required ChatEventRepository chatEventRepository,
    required SessionContextSnapshotRepository snapshotRepository,
    required SessionContextProjector contextProjector,
    required SessionTokenBudgetService tokenBudgetService,
    required SessionSummaryService summaryService,
    required ChatService chatService,
    RuntimeUserContextService? runtimeUserContextService,
    UserContextMessageBuilder? userContextMessageBuilder,
  })  : _chatTurnRepository = chatTurnRepository,
        _chatEventRepository = chatEventRepository,
        _snapshotRepository = snapshotRepository,
        _contextProjector = contextProjector,
        _tokenBudgetService = tokenBudgetService,
        _summaryService = summaryService,
        _chatService = chatService,
        _runtimeUserContextService =
            runtimeUserContextService ?? RuntimeUserContextService(),
        _userContextMessageBuilder =
            userContextMessageBuilder ?? const UserContextMessageBuilder();

  final ChatTurnRepository _chatTurnRepository;
  final ChatEventRepository _chatEventRepository;
  final SessionContextSnapshotRepository _snapshotRepository;
  final SessionContextProjector _contextProjector;
  final SessionTokenBudgetService _tokenBudgetService;
  final SessionSummaryService _summaryService;
  final ChatService _chatService;
  final RuntimeUserContextService _runtimeUserContextService;
  final UserContextMessageBuilder _userContextMessageBuilder;

  Future<List<ChatMessage>> buildPlannerMessages({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    final state = await buildPlannerContextState(
      groupId: groupId,
      currentTurnId: currentTurnId,
      currentTurnTranscript: currentTurnTranscript,
      config: config,
    );
    return [
      state.runtimeUserContextMessage,
      if (state.activeSnapshot != null)
        _contextProjector.projectSnapshotToContext(state.activeSnapshot!.summaryText),
      ...state.recentSegments.expand((segment) => segment.messages),
      ...state.currentTurnMessages,
    ];
  }

  Future<SessionContextBuildResult> buildPlannerContextState({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    final snapshot = await _snapshotRepository.getLatestByGroup(groupId);
    final currentTurn = await _chatTurnRepository.getTurn(currentTurnId);
    final modelName = _chatService.getModelName(config);
    final profile = _tokenBudgetService.resolveProfile(modelName);
    final compactionConfig = profile.compactionConfig;

    final allTurns = await _chatTurnRepository.getTurnsByGroup(groupId);
    final completedTurns = allTurns.where((turn) {
      final turnId = turn.id;
      if (turnId == null || turnId >= currentTurnId) {
        return false;
      }
      if (snapshot != null && turnId <= snapshot.coveredUntilTurnId) {
        return false;
      }
      return turn.status == ChatTurnStatus.completed;
    }).toList(growable: false);

    final groupedHistoryEvents = await _loadHistoryEventsByTurn(
      groupId: groupId,
      allowedTurnIds: completedTurns.map((turn) => turn.id!).toSet(),
    );
    final historySegments = _buildHistorySegments(
      historyTurns: completedTurns,
      groupedEvents: groupedHistoryEvents,
    );
    final userContextMessage = _userContextMessageBuilder.buildMessage(
      snapshot: await _runtimeUserContextService.buildSnapshot(),
    );
    final currentItems = <ModelContextItem>[
      if (_extractDateReminderMessage(currentTurn) case final reminder?)
        ..._contextProjector.projectMessagesToContextItems([reminder]),
      ..._contextProjector.projectEventsToContextItems(currentTurnTranscript),
    ];
    final normalizedCurrentMessages =
        _contextProjector.encodeContextItems(currentItems);
    final resolvedSystemPrompt = _resolveSystemPrompt(config);
    final systemPromptTokens =
        _tokenBudgetService.estimateTextTokens(resolvedSystemPrompt);
    final runtimeUserContextTokens =
        _tokenBudgetService.estimateMessagesTokens([userContextMessage]);
    final fixedPrefixTokens = systemPromptTokens + runtimeUserContextTokens;
    final currentTurnTokens =
        _tokenBudgetService.estimateMessagesTokens(normalizedCurrentMessages);

    var activeSummary = snapshot;
    var recentSegments = _selectRecentCompletedTurns(
      historySegments: historySegments,
      usableInputBudget: profile.usableInputBudget,
      compactionConfig: compactionConfig,
    );
    var didCompactHistory = false;

    var budget = _tokenBudgetService.evaluatePlannerBudget(
      modelName: modelName,
      fixedPrefixTokens: fixedPrefixTokens,
      summaryTokens: _resolveSnapshotTokens(activeSummary),
      recentTurnsTokens: _estimateSegmentsTokens(recentSegments),
      currentTurnTokens: currentTurnTokens,
    );

    if (budget.shouldCompact) {
      final compactionResult = await _compactHistory(
        groupId: groupId,
        existingSnapshot: activeSummary,
        historySegments: historySegments,
        initialRecentSegments: recentSegments,
        modelName: modelName,
        fixedPrefixTokens: fixedPrefixTokens,
        currentTurnTokens: currentTurnTokens,
        compactionConfig: compactionConfig,
      );
      activeSummary = compactionResult.snapshot;
      recentSegments = compactionResult.recentSegments;
      didCompactHistory = compactionResult.didCompactHistory;
    } else {
      budget = _tokenBudgetService.evaluatePlannerBudget(
        modelName: modelName,
        fixedPrefixTokens: fixedPrefixTokens,
        summaryTokens: _resolveSnapshotTokens(activeSummary),
        recentTurnsTokens: _estimateSegmentsTokens(recentSegments),
        currentTurnTokens: currentTurnTokens,
      );
    }

    return SessionContextBuildResult(
      modelName: modelName,
      resolvedSystemPrompt: resolvedSystemPrompt,
      systemPromptTokens: systemPromptTokens,
      runtimeUserContextMessage: userContextMessage,
      runtimeUserContextTokens: runtimeUserContextTokens,
      activeSnapshot: activeSummary,
      recentSegments: recentSegments,
      currentTurnMessages: normalizedCurrentMessages,
      budgetEvaluation: budget,
      didCompactHistory: didCompactHistory,
    );
  }

  Future<Map<int, List<ChatEvent>>> _loadHistoryEventsByTurn({
    required int groupId,
    required Set<int> allowedTurnIds,
  }) async {
    if (allowedTurnIds.isEmpty) {
      return const {};
    }
    final events = await _chatEventRepository.listEventsByGroup(groupId);
    final grouped = <int, List<ChatEvent>>{};
    for (final event in events) {
      if (!allowedTurnIds.contains(event.turnId)) {
        continue;
      }
      grouped.putIfAbsent(event.turnId, () => <ChatEvent>[]).add(event);
    }
    return grouped;
  }

  List<SessionContextTurnSegment> _buildHistorySegments({
    required List<ChatTurn> historyTurns,
    required Map<int, List<ChatEvent>> groupedEvents,
  }) {
    final projected = <SessionContextTurnSegment>[];
    for (final turn in historyTurns) {
      final turnId = turn.id;
      if (turnId == null) {
        continue;
      }
      final messages = _contextProjector.projectEventsToContext(
        groupedEvents[turnId] ?? const [],
      );
      if (messages.isEmpty) {
        continue;
      }
      projected.add(
        SessionContextTurnSegment(
          turnId: turnId,
          messages: messages,
          estimatedTokens: _tokenBudgetService.estimateMessagesTokens(messages),
        ),
      );
    }
    return projected;
  }

  List<SessionContextTurnSegment> _selectRecentCompletedTurns({
    required List<SessionContextTurnSegment> historySegments,
    required int usableInputBudget,
    required ContextCompactionConfig compactionConfig,
  }) {
    if (historySegments.isEmpty) {
      return const [];
    }

    final startIndex = historySegments.length >
            compactionConfig.defaultRecentCompletedTurns
        ? historySegments.length - compactionConfig.defaultRecentCompletedTurns
        : 0;
    final selected = historySegments.sublist(startIndex).toList(growable: true);
    final maxRecentTokens =
        (usableInputBudget * compactionConfig.recentTurnsMaxRatio).floor();

    while (selected.length > compactionConfig.minRecentCompletedTurns &&
        _estimateSegmentsTokens(selected) > maxRecentTokens) {
      selected.removeAt(0);
    }

    return selected.toList(growable: false);
  }

  Future<_CompactionResult> _compactHistory({
    required int groupId,
    required SessionContextSnapshot? existingSnapshot,
    required List<SessionContextTurnSegment> historySegments,
    required List<SessionContextTurnSegment> initialRecentSegments,
    required String modelName,
    required int fixedPrefixTokens,
    required int currentTurnTokens,
    required ContextCompactionConfig compactionConfig,
  }) async {
    final targetHistoryTokens =
        (_tokenBudgetService.resolveProfile(modelName).usableInputBudget *
                compactionConfig.postCompressionHistoryRatio)
            .floor();
    final recentSegments = initialRecentSegments.toList(growable: true);
    final compactedSegments = historySegments
        .take(historySegments.length - recentSegments.length)
        .toList(growable: true);

    SessionContextSnapshot? activeSnapshot = existingSnapshot;

    while (recentSegments.length > compactionConfig.minRecentCompletedTurns &&
        _resolveSnapshotTokens(activeSnapshot) +
                _estimateSegmentsTokens(recentSegments) >
            targetHistoryTokens) {
      compactedSegments.add(recentSegments.removeAt(0));
    }

    if (compactedSegments.isNotEmpty) {
      activeSnapshot = await _rollSummaryForward(
        groupId: groupId,
        existingSnapshot: existingSnapshot,
        compactedSegments: compactedSegments,
      );
      if (activeSnapshot == null) {
        Logger.w(
          _tag,
          'summary compaction skipped because summary generation failed',
        );
        return _CompactionResult(
          snapshot: existingSnapshot,
          recentSegments: historySegments.toList(growable: false),
          didCompactHistory: false,
        );
      }
    }

    return _CompactionResult(
      snapshot: activeSnapshot,
      recentSegments: recentSegments.toList(growable: false),
      didCompactHistory: compactedSegments.isNotEmpty,
    );
  }

  Future<SessionContextSnapshot?> _rollSummaryForward({
    required int groupId,
    required SessionContextSnapshot? existingSnapshot,
    required List<SessionContextTurnSegment> compactedSegments,
  }) async {
    try {
      final summary = await _summaryService.summarizeHistory(
        previousSummary: existingSnapshot?.summaryText,
        historicalMessages:
            compactedSegments.expand((segment) => segment.messages).toList(),
      );
      final snapshot = SessionContextSnapshot(
        groupId: groupId,
        summaryText: summary.summaryText,
        coveredUntilTurnId: compactedSegments.last.turnId,
        estimatedTokens: summary.estimatedTokens,
      );
      await _snapshotRepository.upsertLatest(snapshot);
      return snapshot;
    } catch (error) {
      Logger.w(
        _tag,
        'failed to roll summary forward: $error',
      );
      return null;
    }
  }

  int _estimateSegmentsTokens(Iterable<SessionContextTurnSegment> segments) {
    return segments.fold<int>(0, (total, item) => total + item.estimatedTokens);
  }

  int _resolveSnapshotTokens(SessionContextSnapshot? snapshot) {
    if (snapshot == null) {
      return 0;
    }
    if (snapshot.estimatedTokens > 0) {
      return snapshot.estimatedTokens;
    }
    return _tokenBudgetService.estimateTextTokens(snapshot.summaryText);
  }

  String _resolveSystemPrompt(ChatConfig config) {
    final parts = <String>[
      config.systemPrompt.trim(),
      config.userSystemPrompt.trim(),
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.join('\n');
  }

  ChatMessage? _extractDateReminderMessage(ChatTurn? turn) {
    final runtimeContext = turn?.providerStateJson?[
        SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return null;
    }
    final reminder =
        runtimeContext[SessionRuntimeMarkerService.dateChangeReminderKey];
    if (reminder is! String || reminder.trim().isEmpty) {
      return null;
    }
    return ChatMessage(
      text: reminder,
      role: MessageRole.user,
      status: MessageStatus.completed,
    );
  }
}

class _CompactionResult {
  final SessionContextSnapshot? snapshot;
  final List<SessionContextTurnSegment> recentSegments;
  final bool didCompactHistory;

  const _CompactionResult({
    required this.snapshot,
    required this.recentSegments,
    required this.didCompactHistory,
  });
}
