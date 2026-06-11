import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
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

  group('SessionContextService active-turn compaction', () {
    test(
        'detects active-turn compaction candidate when current transcript exceeds trigger',
        () async {
      final storage = DatabaseHelper(
        databaseName:
            'session_context_service_active_turn_compaction_plan_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(
          title: 'Active Turn Compaction Plan',
          lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
        ),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续当前任务',
        ),
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        chatStorage: storage,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 300,
            reservedOutputTokens: 50,
            safetyMarginTokens: 20,
            pressureThreshold: 0.8,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (_) async =>
              '<summary>Current Work: continue task</summary>',
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final transcript = [
        ChatEvent(
          turnId: currentTurnId,
          groupId: groupId,
          sequence: 1,
          eventType: ChatEventType.userMessage,
          role: MessageRole.user,
          content: 'old user message before compaction',
        ),
        ChatEvent(
          turnId: currentTurnId,
          groupId: groupId,
          sequence: 2,
          eventType: ChatEventType.toolResult,
          role: MessageRole.assistant,
          content: '已执行联网搜索',
          payloadJson: const {
            'toolName': 'web_search',
            'status': 'success',
            'summary': '已执行联网搜索',
            'providerCallId': 'call_web_1',
            'data': {
              'query': 'Claude latest news 2026',
              'results': [
                {
                  'title': 'Claude latest update',
                  'url': 'https://example.com/claude-latest',
                  'snippet':
                      'a very long snippet used to push the current turn over the trigger threshold',
                },
              ],
            },
          },
        ),
      ];

      final plan = await service.planActiveTurnCompaction(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: transcript,
        config: ChatConfig(systemPrompt: '你是一个助手'),
        boundaryEventId: 2,
      );

      expect(plan, isNotNull);
      expect(plan!.coveredUntilTurnId, currentTurnId);
      expect(plan.coveredUntilEventId, 2);
      expect(plan.continuationSummaryText, contains('Current Work'));

      await storage.deleteGroup(groupId);
    });

    test(
        'applies active-turn compaction by persisting rolled summary and boundary',
        () async {
      final storage = DatabaseHelper(
        databaseName:
            'session_context_service_active_turn_compaction_apply_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(
          title: 'Active Turn Compaction Apply',
          lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
        ),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final previousTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: '上一轮任务',
        ),
      );
      await eventRepository.appendUserMessage(
        turnId: previousTurnId,
        groupId: groupId,
        content: '历史用户消息',
      );
      await eventRepository.appendToolResult(
        turnId: previousTurnId,
        groupId: groupId,
        content: '历史工具结果',
        payloadJson: const {
          'toolName': 'search_chat_history',
          'status': 'success',
          'summary': '历史工具结果',
          'providerCallId': 'call_prev_1',
          'data': {
            'query': '历史上下文',
            'matchCount': 1,
          },
        },
      );

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续当前任务',
        ),
      );

      List<ChatMessage>? summarizedMessages;
      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        chatStorage: storage,
        contextProjector: SessionContextProjector(),
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 300,
            reservedOutputTokens: 50,
            safetyMarginTokens: 20,
            pressureThreshold: 0.8,
          ),
        ),
        summaryService: SessionSummaryService(
          summaryGenerator: (messages) async {
            summarizedMessages = List<ChatMessage>.from(messages);
            return '<summary>Current Work: continue task</summary>';
          },
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );

      final transcript = [
        ChatEvent(
          turnId: currentTurnId,
          groupId: groupId,
          sequence: 1,
          eventType: ChatEventType.userMessage,
          role: MessageRole.user,
          content: 'old user message before compaction',
        ),
        ChatEvent(
          turnId: currentTurnId,
          groupId: groupId,
          sequence: 2,
          eventType: ChatEventType.toolResult,
          role: MessageRole.assistant,
          content: '已执行联网搜索',
          payloadJson: const {
            'toolName': 'web_search',
            'status': 'success',
            'summary': '已执行联网搜索',
            'providerCallId': 'call_web_1',
            'data': {
              'query': 'Claude latest news 2026',
              'results': [
                {
                  'title': 'Claude latest update',
                  'url': 'https://example.com/claude-latest',
                  'snippet':
                      'a very long snippet used to push the current turn over the trigger threshold',
                },
              ],
            },
          },
        ),
        ChatEvent(
          turnId: currentTurnId,
          groupId: groupId,
          sequence: 3,
          eventType: ChatEventType.userInteractionResult,
          role: MessageRole.system,
          content: 'new event after compaction',
        ),
      ];

      final result = await service.applyActiveTurnCompaction(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: transcript,
        config: ChatConfig(systemPrompt: '你是一个助手'),
        boundaryEventId: 2,
      );

      expect(result, isNotNull);
      expect(result!.coveredUntilTurnId, currentTurnId);
      expect(result.coveredUntilEventId, 2);
      expect(result.continuationUserInput, '继续当前任务');
      expect(result.didWriteBoundary, isTrue);

      expect(
        summarizedMessages?.skip(1).map((message) => message.text),
        containsAll([
          '历史用户消息',
          contains('search_chat_history'),
          'old user message before compaction',
          contains('web_search query: Claude latest news 2026'),
        ]),
      );

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      expect(snapshot, isNotNull);
      expect(snapshot!.coveredUntilTurnId, currentTurnId);
      expect(snapshot.coveredUntilEventId, 2);
      expect(snapshot.summaryText, contains('Current Work'));

      final events = await eventRepository.listEventsByGroup(groupId);
      expect(
        events.where((event) => event.eventType == ChatEventType.contextCompacted),
        hasLength(1),
      );

      await storage.deleteGroup(groupId);
    });
  });
}

class _FakeBaseLlm extends BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'runtime';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    return '<summary>unused</summary>';
  }
}
