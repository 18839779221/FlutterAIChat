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
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

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
              block.type == AssistantTurnBlockType.toolResultSummary &&
              block.toolResult?.toolName == 'search_chat_history' &&
              block.toolResult?.status == ToolExecutionStatus.success,
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
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

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
              block.type == AssistantTurnBlockType.toolResultSummary &&
              block.toolResult?.toolName == 'search_chat_history' &&
              block.toolResult?.status == ToolExecutionStatus.success,
        ),
        isTrue,
      );

      await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
            pending.message,
            trustTool: true,
          );

      expect(container.read(activePendingToolConfirmationProvider), isNull);
      expect(
        container.read(messagesProvider).any(
              (message) =>
                  message.contentType == MessageContentType.toolResult &&
                  message.payloadJson?['toolName'] == 'create_reminder' &&
                  message.text == '已创建提醒：交周报',
            ),
        isTrue,
      );
      expect(
        container.read(chatTimelineProjectionProvider).assistantBlocks.any(
              (block) =>
                  block.type == AssistantTurnBlockType.toolResultSummary &&
                  block.toolResult?.toolName == 'create_reminder' &&
                  block.toolResult?.status == ToolExecutionStatus.success,
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
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

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

    test(
        'resumed confirmation loop appends visible failure when max iterations are already exhausted',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': '提醒', 'maxResults': 2},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_search_4'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'create_reminder',
                arguments: {'title': '提醒测试'},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_confirm_4'},
            isTerminal: false,
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
                arguments: {'query': '提醒', 'maxResults': 2},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': '提醒',
                  'matchCount': 1,
                },
              ),
            ),
          ]),
          'create_reminder': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '提醒测试'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：创建提醒',
                requiresConfirmation: true,
              ),
              toolResult: null,
            ),
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '提醒测试'},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：创建提醒',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'create_reminder',
                status: ToolExecutionStatus.success,
                summary: '已创建提醒：提醒测试',
              ),
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(maxIterations: 2),
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先搜索，再准备一个需要确认的提醒。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-max-iteration-after-confirm',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final pending = container.read(activePendingToolConfirmationProvider);
      expect(pending, isNotNull);
      await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
            pending!.message,
            trustTool: true,
          );

      expect(container.read(activePendingToolConfirmationProvider), isNull);
      final failedAssistant = container
          .read(messagesProvider)
          .where((message) =>
              message.role == MessageRole.assistant &&
              message.status == MessageStatus.failed)
          .last;
      expect(failedAssistant.text, contains('已达到工具探索上限'));
      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.failed);
      expect(
        (await turnRepository.getTurn(turnId))!.errorMessage,
        'max_iterations_reached',
      );
    });

    test(
        'resumed confirmation loop preserves tool error payload and still reaches final response',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': '历史', 'maxResults': 2},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_search_5'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': ''},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_confirm_5'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '我改用直接回答继续完成本轮。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'response_id': 'resp_final_5'},
            isTerminal: true,
          ),
        ]),
        availableTools: [
          _searchChatHistoryDefinition,
        ],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: {
          'search_chat_history': _searchChatHistoryDefinition,
        },
        queuedResultsByTool: {
          'search_chat_history': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': '历史', 'maxResults': 2},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': '历史',
                  'matchCount': 1,
                },
              ),
            ),
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': ''},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：搜索历史记录',
                requiresConfirmation: true,
              ),
              toolResult: null,
            ),
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': ''},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.failure,
                summary: '搜索历史记录失败',
                data: {
                  'query': '',
                  'reason': 'empty_query',
                },
                errorMessage: 'empty_query',
                executionPolicy: 'blocked',
                toolAccess: {
                  'toolName': 'search_chat_history',
                  'executionDecision': 'blocked',
                  'executionPolicy': 'blocked',
                  'isVisibleToPlanner': false,
                },
              ),
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先搜一次，再确认一次空查询。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-tool-error-after-confirm',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final pending = container.read(activePendingToolConfirmationProvider);
      expect(pending, isNotNull);

      await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
            pending!.message,
            trustTool: true,
          );

      final errorMessage = container
          .read(messagesProvider)
          .where((message) =>
              message.contentType == MessageContentType.toolResult &&
              message.text == '搜索历史记录失败')
          .last;
      expect(
        errorMessage.payloadJson?['toolAccess']?['executionPolicy'],
        'blocked',
      );
      expect(errorMessage.payloadJson?['errorMessage'], 'empty_query');
      expect(container.read(activePendingToolConfirmationProvider), isNull);
      expect(
        container
            .read(messagesProvider)
            .where((message) =>
                message.role == MessageRole.assistant &&
                message.contentType == MessageContentType.plainText)
            .last
            .text,
        '我改用直接回答继续完成本轮。',
      );
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.completed);
    });

    test(
        'chat send flow projects visible failure for planner_no_terminal_decision',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': '数据库版本', 'maxResults': 2},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_search_6'},
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '我已经拿到结果了，开始整理最终答复。',
            diagnosticCode: 'planner_needs_follow_up',
            providerState: {'response_id': 'resp_followup_6'},
            isTerminal: false,
          ),
        ]),
        availableTools: [
          _searchChatHistoryDefinition,
        ],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: {
          'search_chat_history': _searchChatHistoryDefinition,
        },
        queuedResultsByTool: {
          'search_chat_history': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'search_chat_history',
                arguments: {'query': '数据库版本', 'maxResults': 2},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：搜索历史记录',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': '数据库版本',
                  'matchCount': 1,
                },
              ),
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

      await container.read(chatControllerProvider).sendMessage('先查数据库版本，再继续');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final toolResultMessage = container
          .read(messagesProvider)
          .where((message) =>
              message.contentType == MessageContentType.toolResult &&
              message.text == '已执行：搜索历史记录')
          .last;
      expect(toolResultMessage.payloadJson?['data']?['query'], '数据库版本');

      final failureMessage = container
          .read(messagesProvider)
          .where((message) =>
              message.role == MessageRole.assistant &&
              message.status == MessageStatus.failed)
          .last;
      expect(
        failureMessage.text,
        '这轮工具执行已经结束，但模型没有产出最终答复，所以我先停在这里。你可以让我基于当前结果继续总结，或换一种更聚焦的问法再试一次。',
      );
      expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
      expect(container.read(chatSendStateProvider).isGenerating, isFalse);

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turns = await turnRepository.getTurnsByGroup(groupId);
      expect(turns.single.status, ChatTurnStatus.failed);
      expect(turns.single.errorMessage, 'planner_no_terminal_decision');
    });

    test('tool-use visible reasoning lands in waiting timeline projection',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                sequence: 0,
              ),
            ],
            assistantMessage: '我先整理提醒参数。',
            visibleReasoning: '先确认这一步需要用户授权，再进入工具执行。',
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_reasoning_tool'},
            isTerminal: false,
          ),
        ]),
        availableTools: [
          _createReminderDefinition,
        ],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: {
          'create_reminder': _createReminderDefinition,
        },
        queuedResultsByTool: {
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
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先查一下再总结。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-visible-reasoning',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final assistantMessages = container
          .read(messagesProvider)
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(
        assistantMessages.any(
          (message) =>
              message.reasoningContent == '先确认这一步需要用户授权，再进入工具执行。' &&
              message.payloadJson?['reasoningScope'] == 'tool_use',
        ),
        isTrue,
      );

      final projection = container.read(chatTimelineProjectionProvider);
      expect(
        projection.assistantBlocks.any(
          (block) =>
              block.type == AssistantTurnBlockType.analysis &&
              block.reasoningText == '先确认这一步需要用户授权，再进入工具执行。' &&
              block.payload?['reasoningScope'] == 'tool_use',
        ),
        isTrue,
      );
      expect(
        container.read(activePendingToolConfirmationProvider),
        isNotNull,
      );
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.awaitingToolConfirmation);
    });

    test('final-answer visible reasoning lands in final timeline block',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final planner = AgentPlannerService(
        llm: _QueuedDecisionLLM([
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '根据已有记录，这是整理后的最终答复。',
            visibleReasoning: '资料已经足够，可以直接汇总。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'response_id': 'resp_reasoning_final'},
            isTerminal: true,
          ),
        ]),
        availableTools: const [],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: const {},
        queuedResultsByTool: const {},
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

      final turnRepository = ChatTurnRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '直接总结一下。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-visible-final-reasoning',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final projection = container.read(chatTimelineProjectionProvider);
      expect(
        projection.assistantBlocks.any(
          (block) =>
              block.type == AssistantTurnBlockType.finalResponse &&
              block.reasoningText == '资料已经足够，可以直接汇总。' &&
              block.text == '根据已有记录，这是整理后的最终答复。',
        ),
        isTrue,
      );
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.completed);
    });

    test('skill tool result is visible to the next planner iteration',
        () async {
      final databaseHelper = _createTestDatabaseHelper();
      final toolPolicyService = await _createToolPolicyService();
      final queuedLlm = _QueuedDecisionLLM([
        const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'skill',
              arguments: {'skill': 'edge-to-edge'},
              sequence: 0,
            ),
          ],
          assistantMessage: null,
          diagnosticCode: 'planner_action_call_tool',
          providerState: {'response_id': 'resp_skill_1'},
          isTerminal: false,
        ),
        const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '我会按 Android edge-to-edge 指南处理。',
          diagnosticCode: 'planner_action_respond',
          providerState: {'response_id': 'resp_final_skill'},
          isTerminal: true,
        ),
      ]);
      const skillDefinition = ToolDefinition(
        name: 'skill',
        title: 'Skill',
        descriptionForModel: 'Load an installed skill.',
        argumentSchema: ToolArgumentSchema(
          properties: {
            'skill': ToolArgumentProperty.string(
              description: 'Skill name.',
            ),
          },
          required: ['skill'],
        ),
      );
      final planner = AgentPlannerService(
        llm: queuedLlm,
        availableTools: const [skillDefinition],
        toolPolicyService: toolPolicyService,
      );
      final toolCallService = _QueuedToolCallService(
        chatStorage: databaseHelper,
        definitions: const {'skill': skillDefinition},
        queuedResultsByTool: {
          'skill': Queue.of([
            const ToolPreparationResult(
              toolInvocation: ToolInvocation(
                toolName: 'skill',
                arguments: {'skill': 'edge-to-edge'},
                status: ToolInvocationStatus.running,
                summary: '正在执行工具：Skill',
                requiresConfirmation: false,
              ),
              toolResult: ToolResult(
                toolName: 'skill',
                status: ToolExecutionStatus.success,
                summary: 'Skill loaded: edge-to-edge',
                data: {
                  'skillId': 'edge-to-edge',
                  'name': 'edge-to-edge',
                  'qualifiedPath': '/tmp/skills/edge-to-edge',
                  'baseDirectory': '/tmp/skills/edge-to-edge',
                  'instructionBody': 'Use Android edge-to-edge guidance.',
                },
              ),
            ),
          ]),
        },
      );
      final harness = _createHarness(
        databaseHelper: databaseHelper,
        planner: planner,
        toolCallService: toolCallService,
      );
      final container = await _createContainer(
        databaseHelper: databaseHelper,
        harness: harness,
      );
      addTearDown(container.dispose);

      final groupId = await databaseHelper
          .insertGroup(ChatGroup(title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      container.read(currentGroupProvider.notifier).state =
          ChatGroup(id: groupId, title: 'projection group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);

      final turnRepository = ChatTurnRepository(databaseHelper);
      final eventRepository = ChatEventRepository(databaseHelper);
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '启用 edge-to-edge skill 后继续。',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      await _consumeEventStream(
        container: container,
        groupId: groupId,
        traceTurnId: 'trace-skill-projection',
        agentTurnId: turnId,
        stream: harness.runTurn(
          turn: turn,
          config: ChatConfig(systemPrompt: ''),
        ),
      );

      final transcript = await eventRepository.listEventsByTurn(turnId);
      expect(
        transcript.any(
          (event) =>
              event.eventType == ChatEventType.toolResult &&
              event.payloadJson?['toolName'] == 'skill',
        ),
        isTrue,
      );
      expect(queuedLlm.capturedMessages, hasLength(greaterThanOrEqualTo(2)));
      final secondPlannerContext = queuedLlm.capturedMessages[1]
          .map((message) => message.text)
          .join('\n');
      expect(secondPlannerContext, contains('### Skill: edge-to-edge'));
      expect(
        secondPlannerContext,
        contains('Base directory for this skill: /tmp/skills/edge-to-edge'),
      );
      expect(
        container.read(messagesProvider).any(
              (message) =>
                  message.role == MessageRole.assistant &&
                  message.text == '我会按 Android edge-to-edge 指南处理。',
            ),
        isTrue,
      );
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
  AgentLoopLimits limits = const AgentLoopLimits(maxIterations: 6),
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
    limits: limits,
  );
}

Future<ProviderContainer> _createContainer({
  required DatabaseHelper databaseHelper,
  required TurnHarness harness,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final settingsRepository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => null,
  );
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => databaseHelper),
      sharedPreferencesProvider.overrideWith((ref) => preferences),
      appSettingsRepositoryProvider.overrideWith((ref) => settingsRepository),
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
  final List<List<ChatMessage>> capturedMessages = [];

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'queued-test-llm';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    capturedMessages.add(List<ChatMessage>.unmodifiable(messages));
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
    List<ChatEvent> currentTurnEvents = const <ChatEvent>[],
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
