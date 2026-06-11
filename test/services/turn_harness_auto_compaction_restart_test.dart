import 'dart:collection';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/decision_tool_call_executor.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('auto-compacts active turn and continues in a new continuation turn',
      () async {
    final storage = DatabaseHelper(
      databaseName: 'turn_harness_auto_compaction_restart_test.db',
    );
    final groupId = await storage.insertGroup(
      ChatGroup(
        title: 'Turn Harness Auto Compaction Restart',
        lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
      ),
    );
    final turnRepository = ChatTurnRepository(storage);
    final eventRepository = ChatEventRepository(storage);
    final snapshotRepository = SessionContextSnapshotRepository(storage);
    final turnId = await turnRepository.createTurn(
      ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.running,
        userInput: '先联网查 Claude 最新动态，再继续分析',
      ),
    );
    final turn = (await turnRepository.getTurn(turnId))!;

    final plannerService = _SequencedPlannerService([
      const ModelTurnDecision(
        toolCalls: [
          ModelToolCall(
            providerCallId: 'call_web_1',
            toolName: 'web_search',
            arguments: {'query': 'Claude latest news 2026'},
            sequence: 1,
          ),
        ],
        assistantMessage: null,
        diagnosticCode: 'planner_action_call_tool',
        providerState: {'response_id': 'resp_1'},
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        modelName: 'runtime',
        isTerminal: false,
      ),
      const ModelTurnDecision(
        toolCalls: [],
        assistantMessage: '已基于压缩后的上下文继续完成分析。',
        diagnosticCode: 'planner_action_respond',
        providerState: {'response_id': 'resp_2'},
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        modelName: 'runtime',
        isTerminal: true,
      ),
    ]);

    final sessionContextService = SessionContextService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      snapshotRepository: snapshotRepository,
      chatStorage: storage,
      contextProjector: SessionContextProjector(),
      tokenBudgetService: SessionTokenBudgetService(
        modelBudgetResolver: (_) => const SessionModelBudget(
          maxContextTokens: 2000,
          reservedOutputTokens: 200,
          safetyMarginTokens: 100,
          pressureThreshold: 0.8,
        ),
      ),
      summaryService: SessionSummaryService(
        summaryGenerator: (_) async =>
            '<summary>Current Work: continue researching Claude updates</summary>',
      ),
      chatService: ChatService(llm: _FakeBaseLlm()),
    );

    final harness = TurnHarness(
      plannerService: plannerService,
      turnRepository: turnRepository,
      eventRepository: eventRepository,
      transcriptBuilderService: TranscriptBuilderService(
        eventRepository: eventRepository,
      ),
      turnVerifier: TurnVerifier(),
      toolCallService: ToolCallService(
        toolExecutor: ToolExecutor(chatStorage: storage),
      ),
      decisionToolCallExecutor: _FakeDecisionToolCallExecutor(
        eventRepository: eventRepository,
      ),
      sessionContextService: sessionContextService,
      limits: const AgentLoopLimits(maxIterations: 4),
      chatStorage: storage,
    );

    final emitted = await harness
        .runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: '你是一个助手'),
        )
        .toList();

    expect(
      emitted.map((event) => event.eventType),
      contains(ChatEventType.contextCompacted),
    );

    final turns = await turnRepository.getTurnsByGroup(groupId);
    expect(turns, hasLength(2));
    expect(turns.first.id, turnId);
    expect(turns.first.stopReason, 'auto_compacted_continue');
    expect(turns.first.status, ChatTurnStatus.completed);
    expect(turns.last.id, isNot(turnId));
    expect(turns.last.status, ChatTurnStatus.completed);
    expect(turns.last.finalResponseText, '已基于压缩后的上下文继续完成分析。');

    expect(plannerService.seenTurnIds, hasLength(2));
    expect(plannerService.seenTurnIds.first, turnId);
    expect(plannerService.seenTurnIds.last, isNot(turnId));

    final continuationPlannerInput =
        plannerService.capturedCarrierTexts.last.join('\n');
    expect(continuationPlannerInput, contains('Current Work'));
    expect(
      continuationPlannerInput,
      isNot(contains('web_search query: Claude latest news 2026')),
    );

    await storage.deleteGroup(groupId);
  });
}

class _SequencedPlannerService extends AgentPlannerService {
  final Queue<ModelTurnDecision> _decisions;
  final List<int> seenTurnIds = [];
  final List<List<String>> capturedCarrierTexts = [];

  _SequencedPlannerService(List<ModelTurnDecision> decisions)
      : _decisions = Queue<ModelTurnDecision>.from(decisions),
        super(llm: _FakeBaseLlm());

  @override
  Future<ModelTurnDecision?> planNextDecision({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required List<ChatTurnStep> steps,
    required ChatConfig config,
    required AgentLoopLimits limits,
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
  }) async {
    seenTurnIds.add(turn.id!);
    capturedCarrierTexts.add(
      carriers.map((carrier) {
        if (carrier is SyntheticCarrier) {
          return carrier.content;
        }
        if (carrier is RawAssistantCarrier) {
          return carrier.rawJson.toString();
        }
        return carrier.toString();
      }).toList(growable: false),
    );
    return _decisions.removeFirst();
  }
}

class _FakeDecisionToolCallExecutor implements DecisionToolCallExecutor {
  final ChatEventRepository eventRepository;
  static final String _longSnippet =
      List<String>.filled(500, 'a very long snippet used to force compaction')
          .join(' ');

  _FakeDecisionToolCallExecutor({
    required this.eventRepository,
  });

  @override
  Stream<DecisionToolExecutionUpdate> executeDecisionToolCalls({
    required ChatTurn turn,
    required ModelTurnDecision decision,
    required ChatConfig config,
    required int consecutiveFailures,
    int? sharedStepId,
  }) async* {
    final toolCall = decision.toolCalls.single;
    final event = await eventRepository.appendToolResult(
      turnId: turn.id!,
      groupId: turn.groupId,
      content: '已执行联网搜索',
      payloadJson: {
        'toolName': toolCall.toolName,
        'status': ToolExecutionStatus.success.name,
        'summary': '已执行联网搜索',
        'providerCallId': toolCall.providerCallId,
        'data': {
          'query': 'Claude latest news 2026',
          'results': [
            {
              'title': 'Claude latest update',
              'url': 'https://example.com/claude-latest',
              'snippet': _longSnippet,
            },
          ],
        },
      },
    );
    yield DecisionToolExecutionUpdate.event(event);
    yield const DecisionToolExecutionUpdate.summary(
      DecisionToolExecutionSummary(
        executedToolCount: 1,
      ),
    );
  }
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
