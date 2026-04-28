import 'dart:async';
import 'dart:collection';

import 'package:ai_chat/controllers/agent_event_processor.dart';
import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/stop_verification_result.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:ai_chat/tools/handlers/ask_user_question_tool_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef _AgentEventProcessorFactory = AgentEventProcessor Function({
  required int groupId,
  required String traceTurnId,
  int? agentTurnId,
  AgentEventHooks hooks,
});

final _agentEventProcessorFactoryProvider =
    Provider<_AgentEventProcessorFactory>((ref) {
  return ({
    required int groupId,
    required String traceTurnId,
    int? agentTurnId,
    AgentEventHooks hooks = const AgentEventHooks(),
  }) {
    return AgentEventProcessor(
      ref: ref,
      groupId: groupId,
      traceTurnId: traceTurnId,
      agentTurnId: agentTurnId,
      hooks: hooks,
    );
  };
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('simulated turn projection integration', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test(
        'multi-iteration ask-user-question loop projects waiting state and clears it after resume',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': 'SQLite', 'maxResults': 3},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_search_1'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'ask_user_question',
                arguments: {
                  'questions': [
                    {
                      'id': 'storage_layer',
                      'header': 'Storage',
                      'question': 'Which storage layer should we use?',
                      'multiSelect': false,
                      'options': [
                        {
                          'label': 'SQLite',
                          'description': 'Local relational store',
                        },
                      ],
                    },
                  ],
                },
                sequence: 0,
                providerCallId: 'ask_call_1',
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_ask_1'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '建议采用 SQLite 方案。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'response_id': 'resp_final_1'},
            isTerminal: true,
          ),
        ]),
        availableTools: [
          _searchChatHistoryDefinition,
          AskUserQuestionToolHandler().definition,
        ],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: {
          'search_chat_history': _searchChatHistoryDefinition,
          'ask_user_question': AskUserQuestionToolHandler().definition,
        },
        queuedResultsByTool: {
          'search_chat_history': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': 'SQLite', 'maxResults': 3},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': 'SQLite',
                  'matchCount': 1,
                },
              ),
              additionalContextMessages: [],
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group');

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先搜索历史，再问我该用哪种存储。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-ask-loop',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final activePrompt = container.read(activeAskUserQuestionMessageProvider);
      expect(activePrompt, isNotNull);
      expect(container.read(activePendingToolConfirmationProvider), isNull);
      final waitingProjection = container.read(chatTimelineProjectionProvider);
      expect(
        waitingProjection.assistantBlocks.any(
          (block) =>
              block.workflowSteps?.any(
                (step) =>
                    step.toolName == 'search_chat_history' &&
                    step.status == ToolWorkflowStepStatus.completed,
              ) ??
              false,
        ),
        isTrue,
      );
      expect(
        waitingProjection.assistantBlocks.any(
          (block) => block.askUserQuestionRequest != null,
        ),
        isTrue,
      );

      await container.read(chatSendCoordinatorProvider).submitQuestionAnswers(
            activePrompt!,
            response: AskUserQuestionResponse.fromJson(const {
              'answersByQuestionId': {
                'storage_layer': 'SQLite',
              },
              'selectedOptionLabelsByQuestionId': {
                'storage_layer': ['SQLite'],
              },
              'freeTextAnswersByQuestionId': {},
            }),
          );

      expect(container.read(activeAskUserQuestionMessageProvider), isNull);
      final resolvedProjection = container.read(chatTimelineProjectionProvider);
      expect(
        resolvedProjection.assistantBlocks.any(
          (block) => block.askUserQuestionResponse != null,
        ),
        isTrue,
      );
      expect(
        resolvedProjection.assistantBlocks.any(
          (block) => block.type == AssistantTurnBlockType.finalResponse,
        ),
        isTrue,
      );
      expect(
        container
            .read(messagesProvider)
            .where((message) =>
                message.role == MessageRole.assistant &&
                message.contentType == MessageContentType.plainText)
            .last
            .text,
        '建议采用 SQLite 方案。',
      );
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.completed);
    });

    test(
        'multi-iteration confirmation loop projects pending confirmation and clears it after resume',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': '周报', 'maxResults': 3},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_search_2'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_confirm_1'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '提醒已经安排好了。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'response_id': 'resp_final_2'},
            isTerminal: true,
          ),
        ]),
        availableTools: [
          _searchChatHistoryDefinition,
          _createReminderDefinition,
        ],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: {
          'search_chat_history': _searchChatHistoryDefinition,
          'create_reminder': _createReminderDefinition,
        },
        queuedResultsByTool: {
          'search_chat_history': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': '周报', 'maxResults': 3},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': '周报',
                  'matchCount': 2,
                },
              ),
              additionalContextMessages: [],
            ),
          ]),
          'create_reminder': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：创建提醒',
                requiresConfirmation: true,
              ),
              toolResult: null,
              additionalContextMessages: [],
            ),
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：创建提醒',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'create_reminder',
                status: ToolExecutionStatus.success,
                summary: '已创建提醒：交周报',
              ),
              additionalContextMessages: [],
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group');

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先搜索历史，再帮我创建交周报提醒。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-confirm-loop',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final pending = container.read(activePendingToolConfirmationProvider);
      expect(pending, isNotNull);
      expect(
        pending!.invocation.status,
        ToolInvocationStatus.awaitingConfirmation,
      );
      final waitingProjection = container.read(chatTimelineProjectionProvider);
      expect(
        waitingProjection.assistantBlocks.any(
          (block) =>
              block.workflowSteps?.any(
                (step) =>
                    step.toolName == 'search_chat_history' &&
                    step.status == ToolWorkflowStepStatus.completed,
              ) ??
              false,
        ),
        isTrue,
      );

      await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
            pending.message,
            trustTool: true,
          );

      expect(container.read(activePendingToolConfirmationProvider), isNull);
      final resolvedProjection = container.read(chatTimelineProjectionProvider);
      expect(
        resolvedProjection.assistantBlocks.any(
          (block) =>
              block.workflowSteps?.any(
                (step) =>
                    step.toolName == 'create_reminder' &&
                    step.status == ToolWorkflowStepStatus.completed &&
                    step.summary == '已创建提醒：交周报',
              ) ??
              false,
        ),
        isTrue,
      );
      expect(
        container.read(messagesProvider).where((message) =>
            message.contentType == MessageContentType.actionConfirmation),
        isEmpty,
      );
      expect(
        container
            .read(messagesProvider)
            .where((message) =>
                message.role == MessageRole.assistant &&
                message.contentType == MessageContentType.plainText)
            .last
            .text,
        '提醒已经安排好了。',
      );
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.completed);
    });

    test(
        'resumed confirmation loop can surface a new pending confirmation in the same turn',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': '会议', 'maxResults': 2},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_search_3'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'create_reminder',
                arguments: {'title': '准备会前材料'},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_confirm_2'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'create_calendar_event',
                arguments: {
                  'title': '项目例会',
                  'startAt': '2026-04-29T10:00:00+08:00',
                },
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_confirm_3'},
            isTerminal: false,
          ),
        ]),
        availableTools: [
          _searchChatHistoryDefinition,
          _createReminderDefinition,
          _createCalendarEventDefinition,
        ],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: {
          'search_chat_history': _searchChatHistoryDefinition,
          'create_reminder': _createReminderDefinition,
          'create_calendar_event': _createCalendarEventDefinition,
        },
        queuedResultsByTool: {
          'search_chat_history': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': '会议', 'maxResults': 2},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': '会议',
                  'matchCount': 1,
                },
              ),
              additionalContextMessages: [],
            ),
          ]),
          'create_reminder': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '准备会前材料'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：创建提醒',
                requiresConfirmation: true,
              ),
              toolResult: null,
              additionalContextMessages: [],
            ),
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '准备会前材料'},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：创建提醒',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'create_reminder',
                status: ToolExecutionStatus.success,
                summary: '已创建提醒：准备会前材料',
              ),
              additionalContextMessages: [],
            ),
          ]),
          'create_calendar_event': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_calendar_event',
                arguments: {
                  'title': '项目例会',
                  'startAt': '2026-04-29T10:00:00+08:00',
                },
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：创建日历事件',
                requiresConfirmation: true,
              ),
              toolResult: null,
              additionalContextMessages: [],
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group'));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group');

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先准备提醒，再看是否还需要建个日历事件。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-followup-confirm',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final firstPending =
          container.read(activePendingToolConfirmationProvider);
      expect(firstPending, isNotNull);
      expect(firstPending!.invocation.toolName, 'create_reminder');

      await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
            firstPending.message,
            trustTool: true,
          );

      final nextPending = container.read(activePendingToolConfirmationProvider);
      expect(nextPending, isNotNull);
      expect(nextPending!.invocation.toolName, 'create_calendar_event');
      expect(container.read(sendPhaseProvider),
          ChatSendPhase.awaitingConfirmation);
      expect(
        container
            .read(messagesProvider)
            .where((message) =>
                message.contentType == MessageContentType.actionConfirmation)
            .length,
        1,
      );
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.awaitingToolConfirmation);
    });
  });
}

int _testDatabaseCounter = 0;

const _searchChatHistoryDefinition = ToolDefinition(
  name: 'search_chat_history',
  title: '搜索聊天记录',
  descriptionForModel: '当需要从当前对话历史中检索已有信息时使用。',
  argumentSchema: ToolArgumentSchema(
    properties: {
      'query': ToolArgumentProperty.string(description: '查询词'),
      'maxResults': ToolArgumentProperty.integer(description: '结果数量'),
    },
    required: ['query'],
  ),
);

const _createReminderDefinition = ToolDefinition(
  name: 'create_reminder',
  title: '创建提醒',
  descriptionForModel: '当用户明确要求创建提醒事项时使用。',
  argumentSchema: ToolArgumentSchema(
    properties: {
      'title': ToolArgumentProperty.string(description: '提醒标题'),
    },
    required: ['title'],
  ),
);

const _createCalendarEventDefinition = ToolDefinition(
  name: 'create_calendar_event',
  title: '创建日历事件',
  descriptionForModel: '当用户明确要求创建日历事件时使用。',
  argumentSchema: ToolArgumentSchema(
    properties: {
      'title': ToolArgumentProperty.string(description: '事件标题'),
      'startAt': ToolArgumentProperty.string(description: '开始时间'),
    },
    required: ['title', 'startAt'],
  ),
);

DatabaseHelper _createTestDatabaseHelper() {
  _testDatabaseCounter += 1;
  return DatabaseHelper(
    databaseName: 'simulated_turn_projection_$_testDatabaseCounter.db',
  );
}

Future<ToolPolicyService> _createToolPolicyService() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return ToolPolicyService(
    repository: AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => null,
    ),
  );
}

TurnHarness _createHarness({
  required DatabaseHelper databaseHelper,
  required AgentPlannerService planner,
  required ToolCallService toolCallService,
}) {
  final eventRepository = ChatEventRepository(databaseHelper);
  return TurnHarness(
    plannerService: planner,
    turnRepository: ChatTurnRepository(databaseHelper),
    eventRepository: eventRepository,
    transcriptBuilderService: TranscriptBuilderService(
      eventRepository: eventRepository,
    ),
    turnVerifier: _AlwaysStopVerifier(),
    toolCallService: toolCallService,
    limits: const AgentLoopLimits(maxIterations: 6),
  );
}

ProviderContainer _createContainer({
  required DatabaseHelper databaseHelper,
  required TurnHarness harness,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      turnHarnessProvider.overrideWith((ref) => harness),
      chatServiceProvider
          .overrideWith((ref) => ChatService(llm: _NoopBaseLLM())),
    ],
  );
}

Future<void> _consumeEventStream({
  required ProviderContainer container,
  required int groupId,
  required String traceTurnId,
  required int agentTurnId,
  required Stream<ChatEvent> stream,
}) async {
  final factory = container.read(_agentEventProcessorFactoryProvider);
  final processor = factory(
    groupId: groupId,
    traceTurnId: traceTurnId,
    agentTurnId: agentTurnId,
  );
  try {
    await for (final event in stream.cast()) {
      await processor.handle(event);
    }
  } finally {
    await processor.dispose();
  }
}

class _AlwaysStopVerifier extends TurnVerifier {
  @override
  Future<StopVerificationResult> verifyCanStop({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    List<ChatTurnStep> steps = const [],
    required String latestAssistantText,
    required AgentLoopLimits limits,
  }) async {
    return const StopVerificationResult(
      canStop: true,
      reason: 'assistant_completed',
    );
  }
}

class _QueuedDecisionLLM extends BaseLLM {
  _QueuedDecisionLLM(List<ModelTurnDecision> decisions)
      : _decisions = Queue.of(decisions);

  final Queue<ModelTurnDecision> _decisions;

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'queued-test-llm';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    if (_decisions.isEmpty) {
      throw StateError('No queued decisions left');
    }
    return _decisions.removeFirst();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    return 'summary';
  }
}

class _QueuedToolCallService extends ToolCallService {
  _QueuedToolCallService({
    required DatabaseHelper chatStorage,
    required Map<String, ToolDefinition> definitions,
    required Map<String, Queue<ToolPreparationResult>> queuedResultsByTool,
  })  : _definitions = definitions,
        _queuedResultsByTool = queuedResultsByTool,
        super(toolExecutor: ToolExecutor(chatStorage: chatStorage));

  final Map<String, ToolDefinition> _definitions;
  final Map<String, Queue<ToolPreparationResult>> _queuedResultsByTool;

  @override
  ToolDefinition? findDefinition(String toolName) {
    return _definitions[toolName];
  }

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    ToolExecutionStartedCallback? onExecutionStarted,
  }) async {
    final queue = _queuedResultsByTool[invocation.toolName];
    if (queue == null || queue.isEmpty) {
      throw StateError('No queued tool result for ${invocation.toolName}');
    }
    final result = queue.removeFirst();
    if (result.executionStarted &&
        onExecutionStarted != null &&
        result.toolInvocation != null &&
        result.toolAccess != null) {
      await onExecutionStarted(
        invocation: result.toolInvocation!,
        toolAccess: result.toolAccess!,
      );
    }
    return result;
  }
}

class _NoopBaseLLM extends BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    return 'summary';
  }
}
