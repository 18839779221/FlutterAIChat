import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/llm/model_capability_source_kind.dart';
import 'package:ai_chat/models/session/context_compaction_config.dart';
import 'package:ai_chat/models/session/context_usage_category.dart';
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/models/session/model_budget_profile.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/session_context_inspector_service.dart';
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

  group('ContextWindowSnapshot', () {
    test('exposes planner, total, and effective ratios separately', () {
      const snapshot = ContextWindowSnapshot(
        modelName: 'gpt-5',
        maxContextTokens: 128000,
        effectiveInputBudget: 104000,
        autoCompactTriggerTokens: 91000,
        totalEstimatedInputTokens: 64000,
        plannerInputUsageRatio: 64000 / 91000,
        totalWindowUsageRatio: 0.5,
        effectiveInputUsageRatio: 64000 / 104000,
        didCompactHistory: false,
        recentCompletedTurnCount: 2,
        segments: [
          ContextWindowSegment(
            type: ContextWindowSegmentType.systemPrompt,
            label: 'system prompt',
            estimatedTokens: 8000,
            shareOfTotalWindow: 8000 / 128000,
            shareOfUsableInput: 8000 / 104000,
            isPlannerVisible: true,
          ),
        ],
      );

      expect(snapshot.totalWindowUsageRatio, 0.5);
      expect(snapshot.plannerInputUsageRatio, greaterThan(0.7));
      expect(snapshot.effectiveInputUsageRatio, greaterThan(0.6));
      expect(snapshot.segments.single.isPlannerVisible, isTrue);
      expect(
        snapshot.segments.single.type,
        ContextWindowSegmentType.systemPrompt,
      );
    });
  });

  group('SessionContextInspectorService', () {
    test(
        'buildLatestWindowSnapshot reports planner-visible segments and reserve segments',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_inspector_service_segments_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(
            title: 'Context Inspector',
            lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);

      final previousTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.completed,
          userInput: '请帮我整理上下文策略',
        ),
      );
      await eventRepository.appendUserMessage(
        turnId: previousTurnId,
        groupId: groupId,
        content: '请帮我整理上下文策略',
      );
      await eventRepository.appendToolCall(
        turnId: previousTurnId,
        groupId: groupId,
        toolName: 'Read',
        arguments: const {'file_path': 'README.md'},
        summary: '准备读取 README',
      );
      await eventRepository.appendToolResult(
        turnId: previousTurnId,
        groupId: groupId,
        content: '已读取 README',
        payloadJson: const {
          'toolName': 'Read',
          'status': 'success',
          'summary': '已读取 README',
          'data': {
            'filePath': 'README.md',
            'message': 'Read README.md successfully',
          },
        },
      );

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续',
        ),
      );

      final sessionContextService = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        chatStorage: storage,
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
      final inspector = SessionContextInspectorService(
        sessionContextService: sessionContextService,
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
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
      );

      final snapshot = await inspector.buildLatestWindowSnapshot(
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
        config: ChatConfig(systemPrompt: '你是一个助手'),
      );

      expect(snapshot.modelName, 'gpt-5.4');
      expect(
        snapshot.segments.map((item) => item.type),
        contains(ContextWindowSegmentType.currentTurnTranscript),
      );
      expect(
        snapshot.segments.map((item) => item.type),
        contains(ContextWindowSegmentType.reservedOutput),
      );
      expect(snapshot.plannerInputUsageRatio, greaterThan(0));
      expect(snapshot.totalWindowUsageRatio, greaterThan(0));
      expect(snapshot.effectiveInputUsageRatio, greaterThan(0));
      expect(
          snapshot.capabilitySource, ModelCapabilitySourceKind.builtInFallback);
      expect(snapshot.categories, isNotEmpty);
      expect(
        snapshot.categories.map((item) => item.type),
        contains(ContextUsageCategoryType.toolResults),
      );
      expect(
        snapshot.categories.map((item) => item.label),
        contains('系统设定'),
      );
      expect(snapshot.topItems, isNotEmpty);
      expect(
          snapshot.topItems.first.displayLabel, contains('Read · README.md'));

      await storage.deleteGroup(groupId);
    });

    test(
        'snapshot exposes compaction metadata when history rolled into summary',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_inspector_service_compaction_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(
            title: 'Context Inspector Compaction',
            lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
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

      final historicalTurnId = await createCompletedTurn(
        'old-turn-1 with long history payload to force compaction',
      );
      await createCompletedTurn(
        'old-turn-2 with long history payload to force compaction',
      );
      await createCompletedTurn(
        'old-turn-3 with long history payload to force compaction',
      );

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: 'current-turn',
        ),
      );

      final sessionContextService = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
        snapshotRepository: snapshotRepository,
        chatStorage: storage,
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
          summaryGenerator: (_) async => '''
当前目标：保留最近上下文
已确认事实：旧历史已经压缩进 snapshot
用户偏好/限制：无
重要工具结论：无
未完成事项：继续 current-turn
风险与下一步：观察 covered turn
''',
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
      );
      final inspector = SessionContextInspectorService(
        sessionContextService: sessionContextService,
        tokenBudgetService: SessionTokenBudgetService(
          modelBudgetResolver: (_) => const SessionModelBudget(
            maxContextTokens: 120,
            reservedOutputTokens: 20,
            safetyMarginTokens: 10,
            pressureThreshold: 0.5,
          ),
        ),
        chatTurnRepository: turnRepository,
        chatEventRepository: eventRepository,
      );

      final snapshot = await inspector.buildLatestWindowSnapshot(
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
        config: ChatConfig(systemPrompt: '你是一个助手'),
      );

      expect(snapshot.didCompactHistory, isTrue);
      expect(
        snapshot.snapshotCoveredUntilTurnId,
        greaterThanOrEqualTo(historicalTurnId),
      );
      expect(snapshot.recentCompletedTurnCount, greaterThan(0));

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
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    return null;
  }

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';
}
