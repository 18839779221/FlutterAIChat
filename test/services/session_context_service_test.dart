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
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
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

      expect(plannerMessages.first.text, contains('当前目标'));
      expect(
        plannerMessages.map((m) => m.text).join('\n'),
        contains('最近工作集：TurnHarness 还没接入'),
      );
      expect(plannerMessages.last.text, contains('TurnHarness 是主入口'));

      await storage.deleteGroup(groupId);
    });

    test('compresses history into a snapshot when budget pressure is high',
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
          userInput: '历史 turn',
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
        content: '我们要实现 Session 上下文管理，并且必须按 token budget 压缩',
      );
      await eventRepository.appendToolResult(
        turnId: historicalTurnId,
        groupId: groupId,
        content: '结果摘要：需要在接近上限时自动触发压缩',
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
      expect(plannerMessages.first.text, contains('当前目标'));
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
            reservedOutputTokens: 40,
            safetyMarginTokens: 20,
            pressureThreshold: 0.85,
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
      expect(plannerMessages.first.text, contains('旧历史已经被压缩'));
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
  });
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
