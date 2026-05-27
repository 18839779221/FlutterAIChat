import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/debug/debug_turn_inspector_projection_service.dart';
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

  test(
      'builds overview timeline and context sections from persisted and runtime facts',
      () async {
    final storage = DatabaseHelper(
      databaseName: 'debug_turn_inspector_projection_test.db',
    );
    final groupId = await storage.insertGroup(
      ChatGroup(title: 'Debug Inspector', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
    );
    final turnRepository = ChatTurnRepository(storage);
    final eventRepository = ChatEventRepository(storage);
    final sessionContextService = SessionContextService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      snapshotRepository: SessionContextSnapshotRepository(storage),
      contextProjector: SessionContextProjector(),
      tokenBudgetService: SessionTokenBudgetService(
        modelBudgetRegistry: ModelBudgetRegistry(),
      ),
      summaryService:
          SessionSummaryService(chatService: ChatService(llm: _FakeBaseLlm())),
      chatService: ChatService(llm: _FakeBaseLlm()),
    );

    final turnId = await turnRepository.createTurn(
      ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.running,
        userInput: '帮我创建一个 artifact',
      ),
    );
    await eventRepository.appendUserMessage(
      turnId: turnId,
      groupId: groupId,
      content: '帮我创建一个 artifact',
    );
    await eventRepository.appendAssistantPlannerMessage(
      turnId: turnId,
      groupId: groupId,
      content: '先规划 artifact 结构',
    );

    final traceRecorder = ChatTraceRecorder();
    traceRecorder.record(
      turnId: 'turn_$turnId',
      stage: ChatTraceStage.sendStart,
      status: ChatTraceStatus.started,
      summary: '开始发送消息',
    );

    final service = DebugTurnInspectorProjectionService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      sessionContextService: sessionContextService,
      traceRecorder: traceRecorder,
      runtimePreviewState: RuntimeStreamingPreviewState(
        messages: [
          RuntimeStreamingPreviewMessage(
            messageId: 'message_1',
            createdAt: DateTime(2026, 5, 5, 18, 0, 0),
            updatedAt: DateTime(2026, 5, 5, 18, 0, 1),
            blocks: [
              RuntimeStreamingPreviewBlock(
                contentBlockId: 'message_1:tool:0',
                blockType: StreamingContentBlockType.toolUse,
                toolUseId: 'call_artifact_1',
                toolName: 'create_artifact',
                text: '{"source":"<div>hello</div>"}',
                createdAt: DateTime(2026, 5, 5, 18, 0, 0),
                updatedAt: DateTime(2026, 5, 5, 18, 0, 1),
              ),
            ],
          ),
        ],
      ),
    );

    final projection = await service.build(groupId: groupId);

    expect(projection.turnOptions, isNotEmpty);
    expect(projection.selectedTurnId, turnId);
    expect(projection.activeTurnOverview, isNotNull);
    expect(projection.activeTurnOverview!.runtimePreviewMessageCount, 1);
    expect(projection.timelineEntries, isNotEmpty);
    expect(
      projection.timelineEntries.any((entry) => entry.kind == 'userMessage'),
      isTrue,
    );
    expect(projection.contextSections, hasLength(greaterThanOrEqualTo(8)));
    expect(
      projection.contextSections.map((item) => item.title),
      containsAll(
        const [
          'Static Prompt Inputs',
          'Planner Messages',
          'Skills',
          'Transcript Events',
          'Provider State',
          'Runtime Preview State',
        ],
      ),
    );

    await storage.deleteGroup(groupId);
  });

  test('builds skills context section from planner context and skill results',
      () async {
    final storage = DatabaseHelper(
      databaseName: 'debug_turn_inspector_skills_projection_test.db',
    );
    final groupId = await storage.insertGroup(
      ChatGroup(title: 'Debug Inspector Skills', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
    );
    final turnRepository = ChatTurnRepository(storage);
    final eventRepository = ChatEventRepository(storage);
    final sessionContextService = SessionContextService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      snapshotRepository: SessionContextSnapshotRepository(storage),
      contextProjector: SessionContextProjector(),
      tokenBudgetService: SessionTokenBudgetService(
        modelBudgetRegistry: ModelBudgetRegistry(),
      ),
      summaryService:
          SessionSummaryService(chatService: ChatService(llm: _FakeBaseLlm())),
      chatService: ChatService(llm: _FakeBaseLlm()),
    );

    final turnId = await turnRepository.createTurn(
      ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.running,
        userInput: '使用 edge-to-edge skill',
      ),
    );
    await eventRepository.appendToolResult(
      turnId: turnId,
      groupId: groupId,
      content: 'Skill loaded: edge-to-edge',
      payloadJson: const {
        'toolName': 'skill',
        'status': 'success',
        'summary': 'Skill loaded: edge-to-edge',
        'data': {
          'skillId': 'edge-to-edge',
          'name': 'edge-to-edge',
          'qualifiedPath': '/tmp/skills/edge-to-edge',
          'baseDirectory': '/tmp/skills/edge-to-edge',
          'instructionBody': 'Use Android edge-to-edge guidance.',
          'instructionBodyTruncated': true,
          'originalInstructionLength': 1200,
        },
      },
    );

    final service = DebugTurnInspectorProjectionService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      sessionContextService: sessionContextService,
      traceRecorder: ChatTraceRecorder(),
    );

    final projection = await service.build(groupId: groupId);
    final skillsSection = projection.contextSections.firstWhere(
      (section) => section.title == 'Skills',
    );
    final rawJson = skillsSection.rawJson as Map<String, dynamic>;
    final invokedSkills = rawJson['invokedSkills'] as List<dynamic>;
    final invoked = invokedSkills.single as Map<String, dynamic>;

    expect(invoked['skillId'], 'edge-to-edge');
    expect(invoked['name'], 'edge-to-edge');
    expect(invoked['projected'], isTrue);
    expect(invoked['instructionBodyTruncated'], isTrue);
    expect(invoked['originalInstructionLength'], 1200);

    final staticSection = projection.contextSections.firstWhere(
      (section) => section.title == 'Static Prompt Inputs',
    );
    final staticRawJson = staticSection.rawJson as Map<String, dynamic>;
    expect(staticRawJson['systemPrompt'], isA<String>());
    expect(staticRawJson['toolList'], isA<List<dynamic>>());
    expect(staticRawJson['skillList'], isA<List<dynamic>>());

    await storage.deleteGroup(groupId);
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
  }) async {
    return '';
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';
}
