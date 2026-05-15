import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/skill/invoked_skill_context.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/prompt/runtime_user_context_service.dart';
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

  group('SessionContextService skills', () {
    test(
        'buildPlannerMessages includes available skills reminder and invoked skill reminder',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_skills_projection_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Skills Projection'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final eventRepository = ChatEventRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '帮我检查这次改动后要不要跑验证',
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
        runtimeUserContextService: RuntimeUserContextService(
          nowProvider: () => DateTime(2026, 5, 9, 10, 0),
          agentsMdProvider: () async => '',
          platformContextProvider: () => const [],
          skillCatalogProvider: () async => const [
            SkillCatalogEntry(
              id: 'verify',
              name: 'verify',
              description: 'Run project verification after code changes.',
              qualifiedPath: 'projectSettings:verify',
              isEnabled: true,
            ),
          ],
        ),
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
            content: '帮我检查这次改动后要不要跑验证',
          ),
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: 'Skill loaded: verify',
            payloadJson: const {
              'toolName': 'skill',
              'status': 'success',
              'summary': 'Skill loaded: verify',
              'data': {
                'skillId': 'verify',
                'name': 'verify',
                'qualifiedPath': 'projectSettings:verify',
                'baseDirectory': '/tmp/skills/verify',
                'instructionBody':
                    'After code changes, verify by:\n1. Run tests',
              },
            },
          ),
        ],
        config: ChatConfig(systemPrompt: '你是一个助手'),
      );

      expect(plannerMessages, hasLength(greaterThanOrEqualTo(3)));
      expect(
        plannerMessages.first.text,
        contains('# currentDate'),
      );
      expect(
        plannerMessages[1].text,
        contains(
          'The following skills are available for use with the Skill tool:',
        ),
      );
      expect(
        plannerMessages[1].text,
        contains('- verify: Run project verification after code changes.'),
      );

      final combined = plannerMessages.map((message) => message.text).join('\n');
      expect(combined, contains('### Skill: verify'));
      expect(combined, contains('Path: projectSettings:verify'));
      expect(
        combined,
        contains('Base directory for this skill: /tmp/skills/verify'),
      );
      expect(combined, contains('After code changes, verify by:'));

      await storage.deleteGroup(groupId);
    });

    test(
        'rebuilds available skills reminder from latest runtime scan after compaction',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_skills_rebuild_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Skills Rebuild'),
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
        'old-turn-1 with enough history content to trigger compaction pressure',
      );
      await createCompletedTurn(
        'old-turn-2 with enough history content to trigger compaction pressure',
      );

      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续',
        ),
      );

      List<SkillCatalogEntry> currentCatalog = const [
        SkillCatalogEntry(
          id: 'verify',
          name: 'verify',
          description: 'Run project verification after code changes.',
          qualifiedPath: 'projectSettings:verify',
          isEnabled: true,
        ),
      ];

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
          summaryGenerator: (_) async => '''
当前目标：继续保留 runtime user context
已确认事实：旧历史需要被压缩
用户偏好/限制：无
已确认决策：每次重建都要重新注入 skills reminder
已否决方案：无
重要工具结论：无
未完成事项：继续当前 turn
风险与下一步：确认重建后的技能列表仍来自最新扫描
''',
        ),
        chatService: ChatService(llm: _FakeBaseLlm()),
        runtimeUserContextService: RuntimeUserContextService(
          nowProvider: () => DateTime(2026, 5, 9, 10, 0),
          agentsMdProvider: () async => '',
          platformContextProvider: () => const [],
          skillCatalogProvider: () async => currentCatalog,
        ),
      );

      final firstPlannerMessages = await service.buildPlannerMessages(
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

      final snapshot = await snapshotRepository.getLatestByGroup(groupId);
      expect(snapshot, isNotNull);
      expect(
        firstPlannerMessages[1].text,
        contains('- verify: Run project verification after code changes.'),
      );

      currentCatalog = const [
        SkillCatalogEntry(
          id: 'edge-to-edge',
          name: 'edge-to-edge',
          description: 'Improve Android edge-to-edge handling.',
          qualifiedPath: 'android:edge-to-edge',
          isEnabled: true,
        ),
      ];

      final secondPlannerMessages = await service.buildPlannerMessages(
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

      expect(
        secondPlannerMessages[1].text,
        contains('- edge-to-edge: Improve Android edge-to-edge handling.'),
      );
      expect(
        secondPlannerMessages[1].text,
        isNot(
          contains('- verify: Run project verification after code changes.'),
        ),
      );

      await storage.deleteGroup(groupId);
    });

    test('explicit skill reminder userMessage is preserved before real user input', () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_service_explicit_skill_test.db',
      );
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Explicit Skill'),
      );
      final turnRepository = ChatTurnRepository(storage);
      final snapshotRepository = SessionContextSnapshotRepository(storage);
      final currentTurnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '请检查这次改动',
        ),
      );

      const invoked = InvokedSkillContext(
        skillId: 'verify',
        name: 'verify',
        qualifiedPath: 'projectSettings:verify',
        baseDirectory: '/tmp/skills/verify',
        instructionBody: 'After code changes, run tests before claiming success.',
      );

      final service = SessionContextService(
        chatTurnRepository: turnRepository,
        chatEventRepository: ChatEventRepository(storage),
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
        runtimeUserContextService: RuntimeUserContextService(
          nowProvider: () => DateTime(2026, 5, 9, 10, 0),
          agentsMdProvider: () async => '',
          platformContextProvider: () => const [],
          skillCatalogProvider: () async => const [],
        ),
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
            content:
                '<system-reminder>\nThe following skills were invoked in this session. Continue to follow these guidelines:\n\n### Skill: verify\nPath: projectSettings:verify\n\nBase directory for this skill: /tmp/skills/verify\n\nAfter code changes, run tests before claiming success.\n</system-reminder>',
            payloadJson: invoked.toJson(),
          ),
          ChatEvent(
            turnId: currentTurnId,
            groupId: groupId,
            sequence: 2,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '请检查这次改动',
          ),
        ],
        config: ChatConfig(systemPrompt: '你是一个助手'),
      );

      final combined = plannerMessages.map((message) => message.text).join('\n\n');
      final skillIndex = combined.indexOf('### Skill: verify');
      final userIndex = combined.indexOf('请检查这次改动');
      expect(skillIndex, isNonNegative);
      expect(userIndex, greaterThan(skillIndex));

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
    required List<ChatMessage> messages,
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
