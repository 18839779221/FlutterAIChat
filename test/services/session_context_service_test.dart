import 'dart:async';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
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

  group('SessionContextService', () {
    test(
        'builds planner messages from snapshot, recent working set, and current turn transcript',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_builder_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final previousTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: '上一轮',
        ),
      );

      await storage.updateTurn(
        ChatTurn(
          id: previousTurnId,
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: '上一轮',
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      );
      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续，帮我把接入点梳理清楚',
        ),
      );
      await storage.updateTurn(
        ChatTurn(
          id: currentTurnId,
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续，帮我把接入点梳理清楚',
          createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );

      await snapshotRepository.upsertLatest(
        SessionContextSnapshot(
          groupId: groupId,
          summaryText: '当前目标：完成 SessionContextService 接入',
          coveredUntilTurnId: previousTurnId - 1,
          estimatedTokens: 120,
        ),
      );

      await eventRepository.appendAssistantPlannerMessage(
        turnId: previousTurnId,
        groupId: groupId,
        content: '最近工作集：TurnHarness 还没接入',
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
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
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '继续，帮我把接入点梳理清楚',
          ),
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '结果摘要：TurnHarness 是主入口',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      expect(plannerMessages.first.text, contains('# currentDate'));
      expect(
        plannerMessages.map((m) => m.text).join('\n'),
        contains('最近工作集：TurnHarness 还没接入'),
      );
      expect(plannerMessages.last.text, contains('TurnHarness 是主入口'));

      await storage.deleteGroup(groupId);
    });

    test('prepends date change reminder before current turn transcript',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_date_reminder_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Date Reminder'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '今天的最新新闻是什么',
          providerStateJson: const {
            'runtime_context': {
              'date_change_reminder':
                  '<system-reminder>\nThe date has changed. Today\'s date is now 2026-04-25.\nDO NOT mention this to the user explicitly because they are already aware.\n</system-reminder>',
            },
          },
        ),
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
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
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '今天的最新新闻是什么',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      expect(plannerMessages.first.text, contains('# currentDate'));
      expect(plannerMessages[1].text, contains('The date has changed.'));
      expect(plannerMessages[2].text, '今天的最新新闻是什么');

      await storage.deleteGroup(groupId);
    });

    test('does not eagerly create snapshot when budget pressure is low',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_no_eager_summary_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context No Eager Summary'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);

      Future<void> createCompletedTurn(String text) async {
        final turnId = await turnRepository.createTurn(
          ChatTurn(
            groupId: groupId,
            status: ChatTurnStatus.completed,
            userInput: text,
          ),
        );
        await eventRepository.appendUserMessage(
          turnId: turnId,
          groupId: groupId,
          content: text,
        );
      }

      for (var i = 1; i <= 7; i += 1) {
        await createCompletedTurn('completed-turn-$i');
      }

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: 'current-turn',
        ),
      );

      var summaryCalls = 0;
      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 10000,
            reservedOutputTokens: 1000,
            safetyMarginTokens: 500,
            pressureThreshold: 0.95,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async {
            summaryCalls += 1;
            return 'unexpected';
          },
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: 'current-turn',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      expect(summaryCalls, 0);
      expect(snapshot, isNull);
      expect(
        plannerMessages.map((message) => message.text).join('\n'),
        isNot(contains('completed-turn-1')),
      );
      expect(
        plannerMessages.map((message) => message.text).join('\n'),
        contains('completed-turn-7'),
      );

      await storage.deleteGroup(groupId);
    });

    test(
        'compresses older completed turns into a snapshot when budget pressure is high',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_compress_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Compress'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final historicalTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: '更早历史 turn',
        ),
      );
      final recentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: '最近历史 turn',
        ),
      );
      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续',
        ),
      );

      await eventRepository.appendUserMessage(
        turnId: historicalTurnId,
        groupId: groupId,
        content: '我们要实现 Session 上下文管理，并且必须按 token budget 压缩，这是更早的历史。',
      );
      await eventRepository.appendToolResult(
        turnId: historicalTurnId,
        groupId: groupId,
        content: '结果摘要：需要在接近上限时自动触发压缩',
      );
      await eventRepository.appendUserMessage(
        turnId: recentTurnId,
        groupId: groupId,
        content: '最近历史：前一个 completed turn 应该保留原文',
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 100,
            reservedOutputTokens: 20,
            safetyMarginTokens: 10,
            pressureThreshold: 0.8,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async => '''
当前目标：实现 Session 上下文管理
已确认事实：需要按 token budget 自动压缩
用户偏好/限制：无
重要工具结论：接近上限时应自动触发压缩
未完成事项：接入 TurnHarness
风险与下一步：验证 snapshot 边界
''',
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '继续',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      expect(snapshot, isNotNull);
      expect(snapshot!.coveredUntilTurnId, historicalTurnId);
      expect(plannerMessages.first.text, contains('# currentDate'));
      expect(
        plannerMessages.map((message) => message.text).join('\n'),
        contains('最近历史：前一个 completed turn 应该保留原文'),
      );
      expect(plannerMessages.last.text, '继续');

      await storage.deleteGroup(groupId);
    });

    test('retains the most recent turns while compressing older history',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_recent_working_set_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Recent Working Set'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);

      Future<int> createHistoricalTurn(String userText, String toolText) async {
        final turnId = await turnRepository.createTurn(
          ChatTurn(
            groupId: groupId,
            status: ChatTurnStatus.completed,
            userInput: userText,
          ),
        );
        await eventRepository.appendUserMessage(
          turnId: turnId,
          groupId: groupId,
          content: userText,
        );
        await eventRepository.appendToolResult(
          turnId: turnId,
          groupId: groupId,
          content: toolText,
        );
        return turnId;
      }

      await createHistoricalTurn(
        '旧需求：先完成数据库 schema 调整，并补一段很长的历史讨论以模拟被压缩的早期上下文。'
            '这部分信息主要用于测试 token budget 压力下的旧历史折叠行为。',
        '旧结论：需要补 migration 和 snapshot table，并记录数据库升级边界、回填策略、'
            '历史兼容处理范围等较长文本。',
      );
      await createHistoricalTurn(
        '中间需求：补 Planner 接入点说明，同时补一段较长说明来抬高中间 turn 的 token 成本，'
            '确保需要压缩的前缀不只是一条很短消息。',
        '中间结论：TurnHarness 负责组织 current turn transcript，并且需要把 tool result、'
            'assistant question prompt、user interaction result 做紧凑投影。',
      );
      final recentTurnId = await createHistoricalTurn(
        '最近需求：确认 recent working set 应保留哪些 turn',
        '最近结论：要优先保留最近 turn，再压缩更老部分',
      );

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续完善 token-aware working set',
        ),
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 420,
            reservedOutputTokens: 140,
            safetyMarginTokens: 80,
            pressureThreshold: 0.55,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (messages) async {
            final combined = messages.map((item) => item.text).join('\n');
            expect(combined, contains('旧需求'));
            expect(combined, contains('中间需求'));
            expect(combined, isNot(contains('最近需求')));
            return '''
当前目标：完成 Session 上下文管理
已确认事实：旧历史已经被压缩为 snapshot
用户偏好/限制：优先保留最近 turns
重要工具结论：需要 token-aware working set
未完成事项：继续验证保留边界
风险与下一步：观察 snapshot 覆盖范围
''';
          },
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '继续完善 token-aware working set',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      expect(snapshot, isNotNull);
      expect(snapshot!.coveredUntilTurnId, lessThan(recentTurnId));
      expect(plannerMessages.first.text, contains('# currentDate'));
      expect(
        plannerMessages.map((message) => message.text).join('\n'),
        contains('最近需求：确认 recent working set 应保留哪些 turn'),
      );
      expect(
        plannerMessages.map((message) => message.text).join('\n'),
        isNot(contains('旧需求：先完成数据库 schema 调整')),
      );

      await storage.deleteGroup(groupId);
    });

    test('keeps current turn separate from recent completed turns', () async {
      final storage = DatabaseHelper(
        databaseName:
            'session_context_service_no_duplicate_current_turn_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Current Turn Boundary'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);

      final previousTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: 'turn-29-user',
        ),
      );
      await eventRepository.appendUserMessage(
        turnId: previousTurnId,
        groupId: groupId,
        content: 'turn-29-user',
      );

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: 'turn-30-user',
        ),
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetRegistry: ModelBudgetRegistry(
            profiles: {
              'gpt-5.4': const ModelBudgetProfile(
                modelId: 'gpt-5.4',
                maxContextTokens: 10000,
                reservedOutputTokens: 1000,
                reasoningReserveTokens: 500,
                safetyMarginTokens: 500,
                compactionConfig: ContextCompactionConfig(),
              ),
            },
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async => throw UnimplementedError(),
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: 'turn-30-user',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      final combined =
          plannerMessages.map((message) => message.text).join('\n');
      expect(_countOccurrences(combined, 'turn-30-user'), 1);
      expect(combined, contains('turn-29-user'));

      await storage.deleteGroup(groupId);
    });

    test('caps recent completed turns by configured count and ratio', () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_recent_ratio_limit_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Recent Ratio Limit'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);

      Future<int> createCompletedTurn(String text) async {
        final turnId = await turnRepository.createTurn(
          ChatTurn(
            groupId: groupId,
            status: ChatTurnStatus.completed,
            userInput: text,
          ),
        );
        await eventRepository.appendUserMessage(
          turnId: turnId,
          groupId: groupId,
          content: text,
        );
        return turnId;
      }

      await createCompletedTurn('turn-1 old context that should be summarized');
      final secondTurnId = await createCompletedTurn(
          'turn-2 also old context that should be summarized');
      await createCompletedTurn(
          'turn-3 previous completed turn that must remain');

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: 'turn-4 current',
        ),
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetRegistry: ModelBudgetRegistry(
            profiles: {
              'gpt-5.4': const ModelBudgetProfile(
                modelId: 'gpt-5.4',
                maxContextTokens: 300,
                reservedOutputTokens: 100,
                reasoningReserveTokens: 50,
                safetyMarginTokens: 80,
                compactionConfig: ContextCompactionConfig(
                  compressionTriggerRatio: 0.35,
                  postCompressionHistoryRatio: 0.15,
                  defaultRecentCompletedTurns: 3,
                  recentTurnsMaxRatio: 0.10,
                  minRecentCompletedTurns: 1,
                ),
              ),
            },
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (messages) async {
            final combined = messages.map((item) => item.text).join('\n');
            expect(combined, contains('turn-1 old context'));
            expect(combined, contains('turn-2 also old context'));
            return '''
当前目标：保留最近 completed turn
已确认事实：旧历史进入 summary
用户偏好/限制：无
已确认决策：recent turns 需要压缩
已否决方案：无
重要工具结论：无
未完成事项：继续处理 turn-4
风险与下一步：观察 recent ratio
''';
          },
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: 'turn-4 current',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      final combined =
          plannerMessages.map((message) => message.text).join('\n');
      expect(combined,
          contains('turn-3 previous completed turn that must remain'));
      expect(combined, isNot(contains('turn-2 also old context')));
      expect(combined, isNot(contains('turn-1 old context')));

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      expect(snapshot, isNotNull);
      expect(snapshot!.coveredUntilTurnId, secondTurnId);

      await storage.deleteGroup(groupId);
    });

    test('keeps conversation running when summary generation fails', () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_summary_failure_fallback_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Summary Failure Fallback'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);

      Future<void> createCompletedTurn(String text) async {
        final turnId = await turnRepository.createTurn(
          ChatTurn(
            groupId: groupId,
            status: ChatTurnStatus.completed,
            userInput: text,
          ),
        );
        await eventRepository.appendUserMessage(
          turnId: turnId,
          groupId: groupId,
          content: text,
        );
      }

      await createCompletedTurn(
          'old-turn-1 with long history payload to force compaction');
      await createCompletedTurn(
          'old-turn-2 with long history payload to force compaction');
      await createCompletedTurn(
          'old-turn-3 with long history payload to force compaction');

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: 'current-turn',
        ),
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 120,
            reservedOutputTokens: 20,
            safetyMarginTokens: 10,
            pressureThreshold: 0.5,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async => throw StateError('session_summary_empty'),
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final plannerMessages = await service.buildPlannerMessages(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: [
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: 'current-turn',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: '你是一个助手'),
      );

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      final combined =
          plannerMessages.map((message) => message.text).join('\n');
      expect(snapshot, isNull);
      expect(combined, contains('old-turn-1'));
      expect(combined, contains('old-turn-2'));
      expect(combined, contains('old-turn-3'));
      expect(combined, contains('current-turn'));

      await storage.deleteGroup(groupId);
    });
  });
}

int _countOccurrences(String source, String needle) {
  if (needle.isEmpty) {
    return 0;
  }
  var start = 0;
  var count = 0;
  while (true) {
    final index = source.indexOf(needle, start);
    if (index < 0) {
      return count;
    }
    count += 1;
    start = index + needle.length;
  }
}

class _FakeBaseLlm implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'gpt-5.4';

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) =>
      const Stream.empty();

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    return '';
  }

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async {
    return null;
  }

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    return null;
  }

  @override
  Future<String> structureSummaryCard(String sourceText) async => '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
