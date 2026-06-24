import '../models/chat_event.dart';
import '../models/chat/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/context/model_context_item.dart';
import '../models/context/planner_context_carrier.dart';
import '../models/llm/base_llm.dart';
import '../models/llm/llm_config.dart';
import '../models/session/session_runtime_config.dart';
import '../models/llm/resolved_model_budget.dart';
import '../models/response/message_content_type.dart';
import '../models/session/context_compaction_config.dart';
import '../models/session/session_context_snapshot.dart';
import '../models/tool/tool_result.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/chat_event_repository.dart';
import '../repositories/chat_turn_repository.dart';
import '../repositories/session_context_snapshot_repository.dart';
import '../repositories/session_runtime_config_repository.dart';
import '../storage/chat_storage.dart';
import '../utils/logger.dart';
import 'chat_service.dart';
import 'prompt/runtime_user_context_service.dart';
import 'prompt/user_context_message_builder.dart';
import 'memory/memory_runtime_context_service.dart';
import 'session_runtime_marker_service.dart';
import 'session_context_projector.dart';
import 'session_llm_config_resolver.dart';
import 'session_summary_service.dart';
import 'session_token_budget_service.dart';
import 'tool_result_context_projector.dart';

class SessionContextTurnSegment {
  final int turnId;
  final List<ChatMessage> messages;
  final List<PlannerContextCarrier> carriers;
  final int estimatedTokens;

  const SessionContextTurnSegment({
    required this.turnId,
    required this.messages,
    required this.carriers,
    required this.estimatedTokens,
  });
}

class SessionContextBuildResult {
  final String modelName;
  final ResolvedModelBudget resolvedBudget;
  final String resolvedSystemPrompt;
  final int systemPromptTokens;
  final List<ChatMessage> runtimeUserContextMessages;
  final int runtimeUserContextTokens;
  final SessionContextSnapshot? activeSnapshot;
  final List<SessionContextTurnSegment> recentSegments;
  final List<ChatMessage> currentTurnMessages;
  final SessionPlannerBudgetEvaluation budgetEvaluation;
  final bool didCompactHistory;

  const SessionContextBuildResult({
    required this.modelName,
    required this.resolvedBudget,
    required this.resolvedSystemPrompt,
    required this.systemPromptTokens,
    required this.runtimeUserContextMessages,
    required this.runtimeUserContextTokens,
    required this.activeSnapshot,
    required this.recentSegments,
    required this.currentTurnMessages,
    required this.budgetEvaluation,
    required this.didCompactHistory,
  });

  List<ChatMessage> get plannerMessages => [
        ...runtimeUserContextMessages,
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

class ManualSessionCompactionResult {
  final SessionContextSnapshot? snapshot;
  final bool didCompactHistory;

  const ManualSessionCompactionResult({
    required this.snapshot,
    required this.didCompactHistory,
  });
}

class ActiveTurnCompactionPlan {
  final String continuationSummaryText;
  final int coveredUntilTurnId;
  final int coveredUntilEventId;

  const ActiveTurnCompactionPlan({
    required this.continuationSummaryText,
    required this.coveredUntilTurnId,
    required this.coveredUntilEventId,
  });
}

class ActiveTurnCompactionApplyResult {
  final SessionContextSnapshot snapshot;
  final int coveredUntilTurnId;
  final int coveredUntilEventId;
  final String continuationUserInput;
  final bool didWriteBoundary;
  final ChatEvent? boundaryEvent;

  const ActiveTurnCompactionApplyResult({
    required this.snapshot,
    required this.coveredUntilTurnId,
    required this.coveredUntilEventId,
    required this.continuationUserInput,
    required this.didWriteBoundary,
    this.boundaryEvent,
  });
}

class SessionContextService {
  static const String _tag = 'SessionContextService';
  // Architecture:
  // - docs/architecture/append-only-transcript.md
  // - docs/architecture/session-context-management.md
  //
  // Invariant:
  // - currentTurnTranscript is projected as append-only semantic truth.
  // - provider runtime metadata must not filter transcript events.

  SessionContextService({
    required ChatTurnRepository chatTurnRepository,
    required ChatEventRepository chatEventRepository,
    required SessionContextSnapshotRepository snapshotRepository,
    required ChatStorage chatStorage,
    required SessionContextProjector contextProjector,
    required SessionTokenBudgetService tokenBudgetService,
    required SessionSummaryService summaryService,
    required ChatService chatService,
    RuntimeUserContextService? runtimeUserContextService,
    UserContextMessageBuilder? userContextMessageBuilder,
    ToolResultContextProjector? toolResultContextProjector,
    AppSettingsRepository? settingsRepository,
    SessionRuntimeConfigRepository? runtimeConfigRepository,
    SessionLlmConfigResolver? runtimeConfigResolver,
  })  : _chatTurnRepository = chatTurnRepository,
        _chatEventRepository = chatEventRepository,
        _snapshotRepository = snapshotRepository,
        _chatStorage = chatStorage,
        _contextProjector = contextProjector,
        _tokenBudgetService = tokenBudgetService,
        _summaryService = summaryService,
        _chatService = chatService,
        _runtimeUserContextService =
            runtimeUserContextService ?? RuntimeUserContextService(),
        _userContextMessageBuilder =
            userContextMessageBuilder ?? const UserContextMessageBuilder(),
        _toolResultContextProjector =
            toolResultContextProjector ?? const ToolResultContextProjector(),
        _settingsRepository = settingsRepository,
        _runtimeConfigRepository = runtimeConfigRepository,
        _runtimeConfigResolver = runtimeConfigResolver;

  final ChatTurnRepository _chatTurnRepository;
  final ChatEventRepository _chatEventRepository;
  final SessionContextSnapshotRepository _snapshotRepository;
  final ChatStorage _chatStorage;
  final SessionContextProjector _contextProjector;
  final SessionTokenBudgetService _tokenBudgetService;
  final SessionSummaryService _summaryService;
  final ChatService _chatService;
  final RuntimeUserContextService _runtimeUserContextService;
  final UserContextMessageBuilder _userContextMessageBuilder;
  final ToolResultContextProjector _toolResultContextProjector;
  final AppSettingsRepository? _settingsRepository;
  final SessionRuntimeConfigRepository? _runtimeConfigRepository;
  final SessionLlmConfigResolver? _runtimeConfigResolver;

  Future<ManualSessionCompactionResult> compactCompletedHistoryForGroup({
    required int groupId,
    int? keepRecentCompletedTurns,
  }) async {
    final existingSnapshot =
        await _snapshotRepository.getLatestByGroup(groupId);
    final allTurns = await _chatTurnRepository.getTurnsByGroup(groupId);
    final completedTurns = allTurns.where((turn) {
      final turnId = turn.id;
      if (turnId == null) {
        return false;
      }
      if (existingSnapshot != null &&
          turnId <= existingSnapshot.coveredUntilTurnId) {
        return false;
      }
      return turn.status == ChatTurnStatus.completed;
    }).toList(growable: false);
    if (completedTurns.length <= 1) {
      return ManualSessionCompactionResult(
        snapshot: existingSnapshot,
        didCompactHistory: false,
      );
    }

    final groupedHistoryEvents = await _loadHistoryEventsByTurn(
      groupId: groupId,
      allowedTurnIds: completedTurns.map((turn) => turn.id!).toSet(),
    );
    final historySegments = _buildHistorySegments(
      historyTurns: completedTurns,
      groupedEvents: groupedHistoryEvents,
    );
    if (historySegments.length <= 1) {
      return ManualSessionCompactionResult(
        snapshot: existingSnapshot,
        didCompactHistory: false,
      );
    }

    final keepCount =
        (keepRecentCompletedTurns ?? 1).clamp(0, historySegments.length - 1);
    final compactCount = historySegments.length - keepCount;
    if (compactCount <= 0) {
      return ManualSessionCompactionResult(
        snapshot: existingSnapshot,
        didCompactHistory: false,
      );
    }

    final compactedSegments =
        historySegments.take(compactCount).toList(growable: false);
    final snapshot = await _rollSummaryForward(
      groupId: groupId,
      existingSnapshot: existingSnapshot,
      compactedSegments: compactedSegments,
    );
    if (snapshot != null) {
      await _persistContextCompactedBoundary(
        groupId: groupId,
        turnId: compactedSegments.last.turnId,
      );
    }
    return ManualSessionCompactionResult(
      snapshot: snapshot ?? existingSnapshot,
      didCompactHistory: snapshot != null,
    );
  }

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
      ...state.runtimeUserContextMessages,
      if (state.activeSnapshot != null)
        _contextProjector
            .projectSnapshotToContext(state.activeSnapshot!.summaryText),
      ...state.recentSegments.expand((segment) => segment.messages),
      ...state.currentTurnMessages,
    ];
  }

  /// Carrier-based replacement for [buildPlannerMessages].
  ///
  /// Reuses [buildPlannerContextState] for compaction / budget decisions but
  /// emits a typed [PlannerContextCarrier] list. Adapters consume this
  /// list and decide how to materialize each carrier into wire format.
  Future<List<PlannerContextCarrier>> buildPlannerCarriers({
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
    final carriers = <PlannerContextCarrier>[];

    // (1) runtime user context (system / user messages, our-side synthesized)
    for (final m in state.runtimeUserContextMessages) {
      carriers.add(_chatMessageToSyntheticCarrier(m));
    }

    // (2) compaction snapshot summary (plain text)
    final snapshot = state.activeSnapshot;
    if (snapshot != null) {
      carriers.add(
        SyntheticCarrier.user(
          '<conversation-summary>\n'
          '已压缩历史上下文：\n'
          '${snapshot.summaryText.trim()}\n'
          '</conversation-summary>',
        ),
      );
    }

    // (3) recent history segments (already pre-projected into carriers)
    for (final segment in state.recentSegments) {
      carriers.addAll(segment.carriers);
    }

    // (4) current turn transcript
    final filteredCurrentTurnTranscript = _filterCurrentTurnTranscript(
      snapshot: state.activeSnapshot,
      currentTurnId: currentTurnId,
      currentTurnTranscript: currentTurnTranscript,
    );
    carriers.addAll(_eventsToCarriers(filteredCurrentTurnTranscript));
    carriers.addAll(_attachmentReminderCarriers(filteredCurrentTurnTranscript));

    return carriers;
  }

  Future<ActiveTurnCompactionPlan?> planActiveTurnCompaction({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
    required int boundaryEventId,
  }) async {
    final state = await buildPlannerContextState(
      groupId: groupId,
      currentTurnId: currentTurnId,
      currentTurnTranscript: currentTurnTranscript,
      config: config,
    );
    if (!state.budgetEvaluation.shouldCompact) {
      return null;
    }

    final compactedEvents = currentTurnTranscript
        .where((event) => (event.id ?? event.sequence) <= boundaryEventId)
        .toList(growable: false);
    final sourceMessages = _buildActiveTurnCompactionMessages(
      recentSegments: state.recentSegments,
      compactedEvents: compactedEvents,
    );
    if (sourceMessages.isEmpty) {
      return null;
    }

    final summary = await _summaryService.summarizeHistory(
      previousSummary: state.activeSnapshot?.summaryText,
      historicalMessages: sourceMessages,
    );

    return ActiveTurnCompactionPlan(
      continuationSummaryText: summary.summaryText,
      coveredUntilTurnId: currentTurnId,
      coveredUntilEventId: boundaryEventId,
    );
  }

  Future<ActiveTurnCompactionApplyResult?> applyActiveTurnCompaction({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
    required int boundaryEventId,
  }) async {
    final state = await buildPlannerContextState(
      groupId: groupId,
      currentTurnId: currentTurnId,
      currentTurnTranscript: currentTurnTranscript,
      config: config,
    );
    if (!state.budgetEvaluation.shouldCompact) {
      return null;
    }

    final currentTurn = await _chatTurnRepository.getTurn(currentTurnId);
    if (currentTurn == null) {
      throw StateError('Turn $currentTurnId not found');
    }

    final compactedEvents = currentTurnTranscript
        .where((event) => (event.id ?? event.sequence) <= boundaryEventId)
        .toList(growable: false);
    final sourceMessages = _buildActiveTurnCompactionMessages(
      recentSegments: state.recentSegments,
      compactedEvents: compactedEvents,
    );
    if (sourceMessages.isEmpty) {
      return null;
    }

    final summary = await _summaryService.summarizeHistory(
      previousSummary: state.activeSnapshot?.summaryText,
      historicalMessages: sourceMessages,
    );
    final snapshot = SessionContextSnapshot(
      groupId: groupId,
      summaryText: summary.summaryText,
      coveredUntilTurnId: currentTurnId,
      coveredUntilEventId: boundaryEventId,
      estimatedTokens: summary.estimatedTokens,
    );
    await _snapshotRepository.upsertLatest(snapshot);
    final boundaryEvent = await _persistContextCompactedBoundary(
      groupId: groupId,
      turnId: currentTurnId,
    );
    final persistedSnapshot =
        await _snapshotRepository.getLatestByGroup(groupId) ?? snapshot;

    return ActiveTurnCompactionApplyResult(
      snapshot: persistedSnapshot,
      coveredUntilTurnId: currentTurnId,
      coveredUntilEventId: boundaryEventId,
      continuationUserInput: currentTurn.userInput,
      didWriteBoundary: true,
      boundaryEvent: boundaryEvent,
    );
  }

  SyntheticCarrier _chatMessageToSyntheticCarrier(ChatMessage m) {
    switch (m.role) {
      case MessageRole.system:
        return SyntheticCarrier.system(m.text);
      case MessageRole.user:
        return SyntheticCarrier.user(m.text);
      case MessageRole.assistant:
        // Runtime user-context messages never include assistant role.
        throw StateError(
          'assistant role unexpected in runtimeUserContextMessages',
        );
    }
  }

  Future<SessionContextBuildResult> buildPlannerContextState({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    final snapshot = await _snapshotRepository.getLatestByGroup(groupId);
    final currentTurn = await _chatTurnRepository.getTurn(currentTurnId);
    final runtimeConfig = await _resolveRuntimeConfig(groupId);
    final modelName = runtimeConfig?.model.trim().isNotEmpty == true
        ? runtimeConfig!.model.trim()
        : _chatService.getModelName(config);
    final resolvedBudget = runtimeConfig == null
        ? _tokenBudgetService.resolveBudgetForModelName(modelName)
        : _tokenBudgetService.resolveCachedBudgetForRuntime(runtimeConfig);
    final profile = resolvedBudget.policy;
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
    final userContextMessages = _userContextMessageBuilder.buildMessages(
      snapshot: await _runtimeUserContextService.buildSnapshot(
        groupId: groupId,
        userInput: currentTurn?.userInput,
        sideRuntimeConfigOverride: await _resolveRuntimeConfigForSlot(
          groupId,
          SessionRuntimeSlot.side,
        ),
        sideTaskRunner: _buildSideTaskRunner(),
      ),
    );
    final filteredCurrentTurnTranscript = _filterCurrentTurnTranscript(
      snapshot: snapshot,
      currentTurnId: currentTurnId,
      currentTurnTranscript: currentTurnTranscript,
    );
    final currentItems = <ModelContextItem>[
      ..._contextProjector.projectMessagesToContextItems(
        _extractRuntimeReminderMessages(currentTurn),
      ),
      ..._contextProjector.projectEventsToContextItems(
        filteredCurrentTurnTranscript,
      ),
    ];
    final normalizedCurrentMessages =
        _contextProjector.encodeContextItems(currentItems);
    final resolvedSystemPrompt = _resolveSystemPrompt(config);
    final systemPromptTokens =
        _tokenBudgetService.estimateTextTokens(resolvedSystemPrompt);
    final runtimeUserContextTokens =
        _tokenBudgetService.estimateMessagesTokens(userContextMessages);
    final fixedPrefixTokens = systemPromptTokens + runtimeUserContextTokens;
    final currentTurnTokens =
        _tokenBudgetService.estimateMessagesTokens(normalizedCurrentMessages);

    var activeSummary = snapshot;
    var recentSegments = _selectRecentCompletedTurns(
      historySegments: historySegments,
      usableInputBudget: resolvedBudget.policy.usableInputBudget,
      compactionConfig: compactionConfig,
    );
    var didCompactHistory = false;

    var budget = _tokenBudgetService.evaluatePlannerBudgetForResolvedBudget(
      resolvedBudget: resolvedBudget,
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
        resolvedBudget: resolvedBudget,
        fixedPrefixTokens: fixedPrefixTokens,
        currentTurnTokens: currentTurnTokens,
        compactionConfig: compactionConfig,
      );
      activeSummary = compactionResult.snapshot;
      recentSegments = compactionResult.recentSegments;
      didCompactHistory = compactionResult.didCompactHistory;
    }
    budget = _tokenBudgetService.evaluatePlannerBudgetForResolvedBudget(
      resolvedBudget: resolvedBudget,
      fixedPrefixTokens: fixedPrefixTokens,
      summaryTokens: _resolveSnapshotTokens(activeSummary),
      recentTurnsTokens: _estimateSegmentsTokens(recentSegments),
      currentTurnTokens: currentTurnTokens,
    );

    return SessionContextBuildResult(
      modelName: modelName,
      resolvedBudget: resolvedBudget,
      resolvedSystemPrompt: resolvedSystemPrompt,
      systemPromptTokens: systemPromptTokens,
      runtimeUserContextMessages: userContextMessages,
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
      final events = groupedEvents[turnId] ?? const <ChatEvent>[];
      final messages = _contextProjector.projectEventsToContext(events);
      final carriers = _eventsToCarriers(events);
      if (messages.isEmpty && carriers.isEmpty) {
        continue;
      }
      // Prefer carrier tokens when present (closer to wire reality);
      // fall back to legacy ChatMessage estimation for empty-snapshot turns.
      final tokens = carriers.isNotEmpty
          ? _tokenBudgetService.estimateCarriersTokens(carriers)
          : _tokenBudgetService.estimateMessagesTokens(messages);
      projected.add(
        SessionContextTurnSegment(
          turnId: turnId,
          messages: messages,
          carriers: carriers,
          estimatedTokens: tokens,
        ),
      );
    }
    return projected;
  }

  /// Walks a turn's events and produces the carriers the adapter needs:
  ///   • `userMessage`            → SyntheticCarrier(user)
  ///   • `assistantTurnSnapshot`  → RawAssistantCarrier
  ///   • `userInteractionResult`  → SyntheticCarrier(toolResult)  *if* providerCallId
  ///   • `toolResult` / `toolError` → SyntheticCarrier(toolResult) *if* providerCallId
  ///   • Everything else (fragmented assistant events) → skip
  List<PlannerContextCarrier> _eventsToCarriers(List<ChatEvent> events) {
    final carriers = <PlannerContextCarrier>[];
    for (final event in events) {
      switch (event.eventType) {
        case ChatEventType.userMessage:
          final text = (event.content ?? '').trim();
          final attachments = _attachmentsFromEvent(event);
          if (text.isNotEmpty || attachments.isNotEmpty) {
            carriers.add(
              SyntheticCarrier.user(
                text,
                attachments: attachments,
              ),
            );
          }

        case ChatEventType.assistantTurnSnapshot:
          final payload = event.payloadJson;
          if (payload == null) break;
          final apiStyleName = payload['apiStyle']?.toString();
          final raw = payload['rawAssistantMessage'];
          if (apiStyleName == null || raw is! Map) break;
          final style = ChatTurnProviderStyle.values.firstWhere(
            (e) => e.name == apiStyleName,
            orElse: () => throw StateError(
              'unknown apiStyle in assistantTurnSnapshot: $apiStyleName',
            ),
          );
          carriers.add(
            RawAssistantCarrier(
              apiStyle: style,
              rawJson: Map<String, dynamic>.from(raw),
            ),
          );

        case ChatEventType.assistantPlannerMessage:
          break;

        case ChatEventType.toolResult:
        case ChatEventType.toolError:
        case ChatEventType.userInteractionResult:
          final providerCallId =
              event.payloadJson?['providerCallId']?.toString().trim();
          final content = _toolResultCarrierContent(event);
          if (providerCallId == null ||
              providerCallId.isEmpty ||
              content.isEmpty) {
            break;
          }
          carriers.add(
            SyntheticCarrier.toolResult(
              toolCallId: providerCallId,
              content: content,
            ),
          );

        case ChatEventType.contextCompacted:
          break;

        // UI-only events: skip from LLM round-trip.
        case ChatEventType.assistantTextDelta:
        case ChatEventType.assistantTextFinal:
        case ChatEventType.assistantReasoningDelta:
        case ChatEventType.assistantToolCall:
        case ChatEventType.assistantToolConfirmation:
        case ChatEventType.assistantQuestionPrompt:
        case ChatEventType.toolExecutionStarted:
        case ChatEventType.turnStatus:
        case ChatEventType.finalAnswer:
        case ChatEventType.error:
          break;
      }
    }
    return carriers;
  }

  List<ChatEvent> _filterCurrentTurnTranscript({
    required SessionContextSnapshot? snapshot,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
  }) {
    if (snapshot == null) {
      return currentTurnTranscript;
    }
    if (snapshot.coveredUntilTurnId != currentTurnId) {
      return currentTurnTranscript;
    }
    final coveredUntilEventId = snapshot.coveredUntilEventId;
    if (coveredUntilEventId == null) {
      return currentTurnTranscript;
    }
    return currentTurnTranscript
        .where((event) => (event.id ?? event.sequence) > coveredUntilEventId)
        .toList(growable: false);
  }

  List<PlannerContextCarrier> _attachmentReminderCarriers(
    List<ChatEvent> events,
  ) {
    final imageAttachments = events
        .where((event) => event.eventType == ChatEventType.userMessage)
        .expand(_attachmentsFromEvent)
        .where((attachment) => attachment.kind == ChatAttachmentKind.image)
        .toList(growable: false);
    if (imageAttachments.isEmpty) {
      return const <PlannerContextCarrier>[];
    }
    final count = imageAttachments.length;
    final noun = count == 1 ? 'attachment' : 'attachments';
    return <PlannerContextCarrier>[
      SyntheticCarrier.system(
        '<system-reminder>\n'
        'The user sent $count image $noun in this turn. '
        'Treat those image attachments as part of the current user input even if the text message is empty. '
        'Do not say that no image was provided.\n'
        '</system-reminder>',
      ),
    ];
  }

  List<ChatMessage> _buildActiveTurnCompactionMessages({
    required List<SessionContextTurnSegment> recentSegments,
    required List<ChatEvent> compactedEvents,
  }) {
    return <ChatMessage>[
      ...recentSegments.expand((segment) => segment.messages),
      ..._contextProjector.projectEventsToContext(compactedEvents),
    ];
  }

  List<ChatAttachment> _attachmentsFromEvent(ChatEvent event) {
    final raw = event.payloadJson?['attachments'];
    if (raw is! List) {
      return const <ChatAttachment>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => ChatAttachment.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  String _toolResultCarrierContent(ChatEvent event) {
    final payload = event.payloadJson;
    if (payload != null &&
        (event.eventType == ChatEventType.toolResult ||
            event.eventType == ChatEventType.toolError)) {
      final projected = _toolResultContextProjector
          .projectToContextText(ToolResult.fromJson(payload))
          ?.trim();
      if (projected != null && projected.isNotEmpty) {
        return projected;
      }
      final result = ToolResult.fromJson(payload);
      return _emptyToolResultContent(result);
    }
    return (event.content ?? '').trim();
  }

  String _emptyToolResultContent(ToolResult result) {
    final toolName =
        result.toolName.trim().isEmpty ? 'tool' : result.toolName.trim();
    if (result.status == ToolExecutionStatus.failure) {
      final error = result.errorMessage?.trim();
      return error == null || error.isEmpty
          ? '$toolName failed without a structured error.'
          : '$toolName failed: $error';
    }
    return '$toolName completed with empty result.';
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
    required ResolvedModelBudget resolvedBudget,
    required int fixedPrefixTokens,
    required int currentTurnTokens,
    required ContextCompactionConfig compactionConfig,
  }) async {
    final targetHistoryTokens = (resolvedBudget.policy.usableInputBudget *
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
      await _persistContextCompactedBoundary(
        groupId: groupId,
        turnId: compactedSegments.last.turnId,
      );
    }

    return _CompactionResult(
      snapshot: activeSnapshot,
      recentSegments: recentSegments.toList(growable: false),
      didCompactHistory: compactedSegments.isNotEmpty,
    );
  }

  Future<LLMConfig?> _resolveRuntimeConfig(int groupId) async {
    final runtimeConfigRepository = _runtimeConfigRepository;
    final runtimeConfigResolver = _runtimeConfigResolver;
    if (runtimeConfigRepository != null && runtimeConfigResolver != null) {
      try {
        final runtime = await runtimeConfigRepository.getByGroup(groupId);
        if (runtime != null) {
          return await runtimeConfigResolver.resolve(runtime);
        }
      } catch (_) {}
    }
    final repository = _settingsRepository;
    if (repository == null) {
      return null;
    }
    try {
      return await repository.getLlmConfig();
    } catch (_) {
      return null;
    }
  }

  Future<LLMConfig?> _resolveRuntimeConfigForSlot(
    int groupId,
    SessionRuntimeSlot slot,
  ) async {
    final runtimeConfigRepository = _runtimeConfigRepository;
    final runtimeConfigResolver = _runtimeConfigResolver;
    if (runtimeConfigRepository != null && runtimeConfigResolver != null) {
      try {
        final runtime = await runtimeConfigRepository.getByGroup(groupId);
        if (runtime != null) {
          return await runtimeConfigResolver.resolve(runtime, slot: slot);
        }
      } catch (_) {}
    }
    return null;
  }

  MemorySideTaskRunner? _buildSideTaskRunner() {
    final llm = _chatService.llm;
    if (llm is! RuntimeConfigurableBaseLlm) {
      return null;
    }
    final RuntimeConfigurableBaseLlm runtimeLlm =
        llm as RuntimeConfigurableBaseLlm;
    return (
      List<ChatMessage> messages, {
      required ChatConfig config,
      required String requestLabel,
      Duration? timeout,
    }) {
      return runtimeLlm.runSideTextTaskWithConfig(
        messages,
        config: config,
        requestLabel: requestLabel,
        timeout: timeout,
      );
    };
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

  Future<ChatEvent> _persistContextCompactedBoundary({
    required int groupId,
    required int turnId,
  }) async {
    const boundaryText = '已压缩历史上下文';
    final event = await _chatEventRepository.appendContextCompacted(
      turnId: turnId,
      groupId: groupId,
      content: boundaryText,
    );
    await _chatStorage.insertMessage(
      ChatMessage(
        text: boundaryText,
        role: MessageRole.system,
        status: MessageStatus.completed,
        contentType: MessageContentType.contextBoundary,
      ),
      groupId,
    );
    return event;
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

  List<ChatMessage> _extractRuntimeReminderMessages(ChatTurn? turn) {
    final runtimeContext =
        turn?.providerStateJson?[SessionRuntimeMarkerService.runtimeContextKey];
    if (runtimeContext is! Map) {
      return const <ChatMessage>[];
    }
    final reminders = <ChatMessage>[];
    final dateReminder =
        runtimeContext[SessionRuntimeMarkerService.dateChangeReminderKey];
    if (dateReminder is String && dateReminder.trim().isNotEmpty) {
      reminders.add(
        ChatMessage(
          text: dateReminder,
          role: MessageRole.user,
          status: MessageStatus.completed,
        ),
      );
    }
    final workspaceReminder =
        runtimeContext[SessionRuntimeMarkerService.workspaceChangeReminderKey];
    if (workspaceReminder is String && workspaceReminder.trim().isNotEmpty) {
      reminders.add(
        ChatMessage(
          text: workspaceReminder,
          role: MessageRole.user,
          status: MessageStatus.completed,
        ),
      );
    }
    return reminders;
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
