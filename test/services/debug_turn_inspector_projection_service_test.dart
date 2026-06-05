import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/debug_cache_panel_projection.dart';
import 'package:ai_chat/models/debug/llm_cache_stats_summary.dart';
import 'package:ai_chat/models/debug/debug_turn_inspector_timeline_entry.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/debug/debug_turn_inspector_projection_service.dart';
import 'package:ai_chat/services/debug/llm_cache_stats_service.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('debug inspector reads trace events from transcript traceTurnId payload',
      () async {
    final storage = DatabaseHelper(
      databaseName: 'debug_turn_inspector_trace_turn_id_test.db',
    );
    final turnRepository = ChatTurnRepository(storage);
    final eventRepository = ChatEventRepository(storage);
    final snapshotRepository = SessionContextSnapshotRepository(storage);
    final traceRecorder = ChatTraceRecorder();
    final groupId = await storage.insertGroup(
      ChatGroup(title: 'Debug Trace Inspector', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
    );
    final turnId = await turnRepository.createTurn(
      ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.running,
        userInput: 'trace me',
      ),
    );

    await eventRepository.appendUserMessage(
      turnId: turnId,
      groupId: groupId,
      content: 'trace me',
    );
    await eventRepository.appendAssistantPlannerMessage(
      turnId: turnId,
      groupId: groupId,
      content: 'I will search first.',
      payloadJson: const {
        'traceTurnId': 'trace-runtime-123',
      },
    );

    traceRecorder.record(
      turnId: 'trace-runtime-123',
      stage: ChatTraceStage.sendStart,
      status: ChatTraceStatus.started,
      summary: 'trace start',
    );

    final service = DebugTurnInspectorProjectionService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      sessionContextService: SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        chatStorage: storage,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 10000,
            reservedOutputTokens: 1000,
            safetyMarginTokens: 500,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async => throw UnimplementedError(),
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      ),
      traceRecorder: traceRecorder,
    );

    final projection = await service.buildForTurn(
      groupId: groupId,
      selectedTurnId: turnId,
    );

    expect(
      projection.timelineEntries.any(
        (entry) =>
            entry.source == DebugTurnTimelineSource.trace &&
            entry.summary == 'trace start',
      ),
      isTrue,
    );

    await storage.deleteGroup(groupId);
  });

  test('debug inspector projection includes cache panel projection', () async {
    final storage = DatabaseHelper(
      databaseName: 'debug_turn_inspector_cache_panel_test.db',
    );
    final turnRepository = ChatTurnRepository(storage);
    final eventRepository = ChatEventRepository(storage);
    final snapshotRepository = SessionContextSnapshotRepository(storage);
    final traceRecorder = ChatTraceRecorder();
    final groupId = await storage.insertGroup(
      ChatGroup(
        title: 'Debug Cache Inspector',
        lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
      ),
    );
    final turnId = await turnRepository.createTurn(
      ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.completed,
        userInput: 'cache stats',
      ),
    );

    final service = DebugTurnInspectorProjectionService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      sessionContextService: SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        chatStorage: storage,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 10000,
            reservedOutputTokens: 1000,
            safetyMarginTokens: 500,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async => throw UnimplementedError(),
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      ),
      traceRecorder: traceRecorder,
      cacheStatsService: _FakeLlmCacheStatsService(
        const DebugCachePanelProjection(
          sampleSize: 100,
          sourceLogPath: '/tmp/app.log',
          summary: LlmCacheStatsSummary(
            totalRequests: 3,
            requestsWithUsage: 2,
            hitRequests: 1,
            totalInputTokens: 120,
            hitInputTokens: 60,
          ),
          bucketsByApiStyle: [],
          recentRequests: [],
        ),
      ),
    );

    final projection = await service.buildForTurn(
      groupId: groupId,
      selectedTurnId: turnId,
    );

    expect(projection.cachePanel, isNotNull);
    expect(projection.cachePanel!.summary.totalRequests, 3);
    expect(projection.activeTurnOverview?.turnId, turnId);

    await storage.deleteGroup(groupId);
  });
}

class _FakeBaseLlm extends BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'fake';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    return 'summary';
  }
}

class _FakeLlmCacheStatsService extends LlmCacheStatsService {
  _FakeLlmCacheStatsService(this.projection);

  final DebugCachePanelProjection projection;

  @override
  Future<DebugCachePanelProjection> readRecentStats({
    int sampleSize = 100,
  }) async {
    return projection;
  }
}
