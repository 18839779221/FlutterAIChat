import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/session/session_context_snapshot.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../repositories/session_context_snapshot_repository.dart';
import 'chat_service.dart';
import 'session_context_projector.dart';
import 'session_summary_service.dart';
import 'session_token_budget_service.dart';

class SessionContextService {
  static const int _minimumCompressionReserveTokens = 160;

  SessionContextService({
    required ChatTurnRepository chatTurnRepository,
    required ChatEventRepository chatEventRepository,
    required SessionContextSnapshotRepository snapshotRepository,
    required SessionContextProjector contextProjector,
    required SessionTokenBudgetService tokenBudgetService,
    required SessionSummaryService summaryService,
    required ChatService chatService,
  })  : _chatTurnRepository = chatTurnRepository,
        _chatEventRepository = chatEventRepository,
        _snapshotRepository = snapshotRepository,
        _contextProjector = contextProjector,
        _tokenBudgetService = tokenBudgetService,
        _summaryService = summaryService,
        _chatService = chatService;

  final ChatTurnRepository _chatTurnRepository;
  final ChatEventRepository _chatEventRepository;
  final SessionContextSnapshotRepository _snapshotRepository;
  final SessionContextProjector _contextProjector;
  final SessionTokenBudgetService _tokenBudgetService;
  final SessionSummaryService _summaryService;
  final ChatService _chatService;

  Future<List<ChatMessage>> buildPlannerMessages({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    final snapshot = await _snapshotRepository.getLatestByGroup(groupId);
    final allTurns = await _chatTurnRepository.getTurnsByGroup(groupId);
    final historyTurns = allTurns.where((turn) {
      final turnId = turn.id;
      if (turnId == null || turnId >= currentTurnId) {
        return false;
      }
      if (snapshot != null && turnId <= snapshot.coveredUntilTurnId) {
        return false;
      }
      return true;
    }).toList(growable: false);

    final groupedHistoryEvents = await _loadHistoryEventsByTurn(
      groupId: groupId,
      allowedTurnIds: historyTurns.map((turn) => turn.id!).toSet(),
    );
    final historySegments = _buildHistorySegments(
      historyTurns: historyTurns,
      groupedEvents: groupedHistoryEvents,
    );
    final currentMessages =
        _contextProjector.projectEventsToContext(currentTurnTranscript);

    final modelName = _chatService.getModelName(config);
    final snapshotTokens = snapshot?.estimatedTokens ??
        (snapshot == null
            ? 0
            : _tokenBudgetService.estimateTextTokens(snapshot.summaryText));
    final fixedTokens = _tokenBudgetService.estimateTextTokens(
          _resolveSystemPrompt(config),
        ) +
        _tokenBudgetService.estimateMessagesTokens(currentMessages);
    final historySplit = _planHistorySplit(
      historySegments: historySegments,
      targetHistoryTokens: _resolveTargetHistoryTokens(
        modelName: modelName,
        fixedTokens: fixedTokens,
        snapshotTokens: snapshotTokens,
      ),
    );
    final retainedHistoryMessages = historySplit.retainedSegments
        .expand((segment) => segment.messages)
        .toList(growable: false);
    if (historySplit.segmentsToCompress.isNotEmpty) {
      final projectedToCompress = [
        if (snapshot != null)
          _contextProjector.projectSnapshotToContext(snapshot.summaryText),
        ...historySplit.segmentsToCompress
            .expand((segment) => segment.messages),
      ];
      final summary = await _summaryService.summarize(
        groupId: groupId,
        projectedHistory: projectedToCompress,
      );
      final compressedSnapshot = SessionContextSnapshot(
        groupId: groupId,
        summaryText: summary.summaryText,
        coveredUntilTurnId: historySplit.segmentsToCompress.last.turnId,
        estimatedTokens: summary.estimatedTokens,
      );
      await _snapshotRepository.upsertLatest(compressedSnapshot);
      return [
        _contextProjector.projectSnapshotToContext(summary.summaryText),
        ...retainedHistoryMessages,
        ...currentMessages,
      ];
    }

    return [
      if (snapshot != null)
        _contextProjector.projectSnapshotToContext(snapshot.summaryText),
      ...retainedHistoryMessages,
      ...currentMessages,
    ];
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

  List<_TurnContextSegment> _buildHistorySegments({
    required List<ChatTurn> historyTurns,
    required Map<int, List<ChatEvent>> groupedEvents,
  }) {
    final projected = <_TurnContextSegment>[];
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
        _TurnContextSegment(
          turnId: turnId,
          messages: messages,
          estimatedTokens: _tokenBudgetService.estimateMessagesTokens(messages),
        ),
      );
    }
    return projected;
  }

  int _resolveTargetHistoryTokens({
    required String modelName,
    required int fixedTokens,
    required int snapshotTokens,
  }) {
    final budget = _tokenBudgetService.resolveBudget(modelName);
    final thresholdBudget =
        (budget.inputBudget * budget.pressureThreshold).floor();
    final remaining = thresholdBudget - fixedTokens - snapshotTokens;
    return remaining < 0 ? 0 : remaining;
  }

  _HistorySplitPlan _planHistorySplit({
    required List<_TurnContextSegment> historySegments,
    required int targetHistoryTokens,
  }) {
    if (historySegments.isEmpty) {
      return const _HistorySplitPlan(
        retainedSegments: [],
        segmentsToCompress: [],
      );
    }

    final retainedReversed = <_TurnContextSegment>[];
    var retainedTokens = 0;
    for (final segment in historySegments.reversed) {
      final nextRetainedTokens = retainedTokens + segment.estimatedTokens;
      if (nextRetainedTokens > targetHistoryTokens) {
        break;
      }
      retainedReversed.add(segment);
      retainedTokens = nextRetainedTokens;
    }

    final retainedSegments = retainedReversed.reversed.toList(growable: true);
    var segmentsToCompress = historySegments
        .take(historySegments.length - retainedSegments.length)
        .toList(growable: true);

    while (retainedSegments.isNotEmpty &&
        retainedTokens + _estimateCompressionReserveTokens(segmentsToCompress) >
            targetHistoryTokens) {
      final removed = retainedSegments.removeAt(0);
      retainedTokens -= removed.estimatedTokens;
      segmentsToCompress.add(removed);
    }

    return _HistorySplitPlan(
      retainedSegments: retainedSegments.toList(growable: false),
      segmentsToCompress: historySegments
          .take(historySegments.length - retainedSegments.length)
          .toList(growable: false),
    );
  }

  int _estimateCompressionReserveTokens(
      Iterable<_TurnContextSegment> segments) {
    final sourceTokens =
        segments.fold<int>(0, (total, item) => total + item.estimatedTokens);
    if (sourceTokens <= 0) {
      return 0;
    }
    final estimated = (sourceTokens * 0.25).ceil();
    return estimated < _minimumCompressionReserveTokens
        ? _minimumCompressionReserveTokens
        : estimated;
  }

  String _resolveSystemPrompt(ChatConfig config) {
    final parts = <String>[
      config.systemPrompt.trim(),
      config.userSystemPrompt.trim(),
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.join('\n');
  }
}

class _TurnContextSegment {
  final int turnId;
  final List<ChatMessage> messages;
  final int estimatedTokens;

  const _TurnContextSegment({
    required this.turnId,
    required this.messages,
    required this.estimatedTokens,
  });
}

class _HistorySplitPlan {
  final List<_TurnContextSegment> retainedSegments;
  final List<_TurnContextSegment> segmentsToCompress;

  const _HistorySplitPlan({
    required this.retainedSegments,
    required this.segmentsToCompress,
  });
}
