import 'dart:async';
import 'dart:collection';

import 'package:ai_chat/models/agent/agent_action.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/tool/tool_access_snapshot.dart';
import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/agent/stop_verification_result.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/models/tool/tool_call.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/decision_tool_call_executor.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chat/tools/handlers/fetch_webpage_tool_handler.dart';
import 'package:ai_chat/tools/handlers/glob_tool_handler.dart';
import 'package:ai_chat/tools/handlers/grep_tool_handler.dart';
import 'package:ai_chat/tools/handlers/ls_tool_handler.dart';
import 'package:ai_chat/tools/handlers/read_tool_handler.dart';
import 'package:ai_chat/tools/handlers/search_chat_history_tool_handler.dart';
import 'package:ai_chat/tools/handlers/web_search_tool_handler.dart';
import 'package:ai_chat/tools/handlers/write_tool_handler.dart';

void main() {
  group('TurnHarness', () {
    test('tool definition defaults to non-concurrency-safe', () {
      const definition = ToolDefinition(
        name: 'demo_tool',
        title: 'Demo Tool',
      );

      expect(definition.isConcurrencySafe, isFalse);
    });

    test('read-oriented tools are marked concurrency-safe', () {
      Future<ToolResult> fakeWebSearcher({
        required String query,
        int? maxResults,
      }) async {
        return const ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        );
      }

      Future<ToolResult> fakeWebpageFetcher({
        required String url,
        required String prompt,
      }) async {
        return const ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        );
      }

      Future<ToolResult> fakeChatHistorySearcher({
        required int groupId,
        required String query,
        required int maxResults,
      }) async {
        return const ToolResult(
          toolName: 'search_chat_history',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        );
      }

      expect(ReadToolHandler().definition.isConcurrencySafe, isTrue);
      expect(LsToolHandler().definition.isConcurrencySafe, isTrue);
      expect(GrepToolHandler().definition.isConcurrencySafe, isTrue);
      expect(GlobToolHandler().definition.isConcurrencySafe, isTrue);
      expect(
        WebSearchToolHandler(webSearcher: fakeWebSearcher)
            .definition
            .isConcurrencySafe,
        isTrue,
      );
      expect(
        FetchWebpageToolHandler(webpageFetcher: fakeWebpageFetcher)
            .definition
            .isConcurrencySafe,
        isTrue,
      );
      expect(
        SearchChatHistoryToolHandler(searcher: fakeChatHistorySearcher)
            .definition
            .isConcurrencySafe,
        isTrue,
      );
      expect(WriteToolHandler().definition.isConcurrencySafe, isFalse);
    });

    test('direct terminal planner answer does not stream an extra final answer',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '你是谁？',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '我是你的 AI 助手。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'response_id': 'resp_direct_1'},
            providerStyle: ChatTurnProviderStyle.openaiResponses,
            modelName: 'gpt-5.4',
            isTerminal: true,
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.finalAnswer,
        ]),
      );
      final finalAnswer = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswer.content, '我是你的 AI 助手。');
    });

    test('emits scoped reasoning for tool-use and final-answer decisions',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '查一下资料再总结',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'web_search',
                arguments: {'query': 'OpenAI latest'},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            visibleReasoning: '需要先联网确认最新信息。',
            providerState: {'response_id': 'resp_tool'},
            providerStyle: ChatTurnProviderStyle.openaiResponses,
            modelName: 'gpt-5.4',
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '这是最终总结。',
            visibleReasoning: '已经拿到资料，可以整理答案。',
            providerState: {'response_id': 'resp_final'},
            providerStyle: ChatTurnProviderStyle.openaiResponses,
            modelName: 'gpt-5.4',
            isTerminal: true,
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        decisionToolCallExecutor: _FakeDecisionToolCallExecutor(),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      final reasoningEvents = emitted
          .where((event) =>
              event.eventType == ChatEventType.assistantReasoningDelta)
          .toList();
      expect(reasoningEvents, hasLength(2));
      expect(reasoningEvents.first.content, '需要先联网确认最新信息。');
      expect(
          reasoningEvents.first.payloadJson, containsPair('scope', 'tool_use'));
      expect(reasoningEvents.last.content, '已经拿到资料，可以整理答案。');
      expect(
        reasoningEvents.last.payloadJson,
        containsPair('scope', 'final_answer'),
      );
      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantReasoningDelta,
          ChatEventType.turnStatus,
          ChatEventType.assistantReasoningDelta,
          ChatEventType.turnStatus,
          ChatEventType.finalAnswer,
        ]),
      );
    });

    test(
        'runs tool call, records tool result, then completes with terminal answer',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查数据库版本',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
            ),
            diagnosticCode: 'planner_action_call_tool',
          ),
          const AgentAction.respond(
            '根据工具结果生成最终回答',
            diagnosticCode: 'planner_action_respond',
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolAccess: const ToolAccessSnapshot(
              definition: ToolDefinition(
                name: 'search_chat_history',
                title: '搜索聊天记录',
              ),
              executionDecision: ToolPolicyDecision.autoRun,
              executionPolicyLabel: 'auto_run',
              isVisibleToPlanner: true,
            ),
            toolResult: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已找到数据库版本是 7',
              executionPolicy: 'auto_run',
              toolAccess: {
                'toolName': 'search_chat_history',
                'executionDecision': 'autoRun',
                'executionPolicy': 'auto_run',
                'isVisibleToPlanner': true,
              },
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.turnStatus,
          ChatEventType.finalAnswer,
        ]),
      );
      final finalAnswerEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswerEvent.content, '根据工具结果生成最终回答');
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.completed);
      final turnStatusContents = emitted
          .where((event) => event.eventType == ChatEventType.turnStatus)
          .map((event) => event.content)
          .toList();
      expect(
        turnStatusContents,
        containsAll([
          'planner_action_call_tool:search_chat_history',
          'planner_action_respond',
        ]),
      );
      final toolCallEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.assistantToolCall,
      );
      expect(toolCallEvent.content, '准备执行工具：搜索聊天记录');
      expect(toolCallEvent.payloadJson?['toolName'], 'search_chat_history');
      expect(toolCallEvent.payloadJson?['status'], 'proposed');
      expect(toolCallEvent.payloadJson?['summary'], '准备执行工具：搜索聊天记录');
      final executionStartedEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.toolExecutionStarted,
      );
      expect(executionStartedEvent.content, '正在执行工具：搜索历史');
      expect(executionStartedEvent.payloadJson?['toolName'],
          'search_chat_history');
      expect(executionStartedEvent.payloadJson?['status'], 'running');
      expect(executionStartedEvent.payloadJson?['executionPolicy'], isNull);
      expect(
        executionStartedEvent.payloadJson?['toolAccess']?['executionPolicy'],
        'auto_run',
      );
      final toolResultEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.toolResult,
      );
      expect(toolResultEvent.content, '已找到数据库版本是 7');
      expect(toolResultEvent.content, isNot(contains('命中历史消息')));
      expect(toolResultEvent.payloadJson?['executionPolicy'], isNull);
      expect(
        toolResultEvent.payloadJson?['toolAccess']?['executionPolicy'],
        'auto_run',
      );
    });

    test('turn harness delegates tool decisions to decision executor',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 11,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我读取文件',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final fakeExecutor = _FakeDecisionToolCallExecutor(
        updates: [
          DecisionToolExecutionUpdate.event(
            ChatEvent(
              turnId: turnId,
              groupId: 1,
              sequence: 3,
              eventType: ChatEventType.toolResult,
              role: MessageRole.system,
              content: '已执行工具批次',
            ),
          ),
          const DecisionToolExecutionUpdate.summary(
            DecisionToolExecutionSummary(
              executedToolCount: 1,
              enteredAwaitingConfirmation: true,
              shouldStopFurtherExecution: true,
            ),
          ),
        ],
      );

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'Read',
                arguments: {'file_path': 'foo.txt'},
                sequence: 1,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {},
            isTerminal: false,
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        decisionToolCallExecutor: fakeExecutor,
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(fakeExecutor.executeCalls, hasLength(1));
      expect(
        emitted.map((event) => event.eventType),
        contains(ChatEventType.toolResult),
      );
    });

    test('groups consecutive concurrency-safe tools into batches', () {
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: _InMemoryChatTurnRepository(),
        eventRepository: _InMemoryChatEventRepository(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
          definitionsByName: const {
            'Read': ToolDefinition(
              name: 'Read',
              title: 'Read',
              isConcurrencySafe: true,
            ),
            'Grep': ToolDefinition(
              name: 'Grep',
              title: 'Grep',
              isConcurrencySafe: true,
            ),
            'Write': ToolDefinition(
              name: 'Write',
              title: 'Write',
              isConcurrencySafe: false,
            ),
            'Glob': ToolDefinition(
              name: 'Glob',
              title: 'Glob',
              isConcurrencySafe: true,
            ),
          },
        ),
        limits: const AgentLoopLimits(),
      );

      final batches = executor.debugBuildExecutionBatches([
        const ModelToolCall(
          toolName: 'Read',
          arguments: {'file_path': 'a.txt'},
          sequence: 1,
        ),
        const ModelToolCall(
          toolName: 'Grep',
          arguments: {'pattern': 'foo'},
          sequence: 2,
        ),
        const ModelToolCall(
          toolName: 'Write',
          arguments: {'file_path': 'b.txt', 'content': 'x'},
          sequence: 3,
        ),
        const ModelToolCall(
          toolName: 'Read',
          arguments: {'file_path': 'c.txt'},
          sequence: 4,
        ),
        const ModelToolCall(
          toolName: 'Glob',
          arguments: {'pattern': '*.md'},
          sequence: 5,
        ),
      ]);

      expect(
        batches
            .map((batch) =>
                batch.toolCalls.map((call) => call.toolName).toList())
            .toList(),
        [
          ['Read', 'Grep'],
          ['Write'],
          ['Read', 'Glob'],
        ],
      );
      expect(
        batches.map((batch) => batch.isConcurrent).toList(),
        [true, false, true],
      );
    });

    test('pauses turn when tool requires confirmation', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 2,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '提醒我明晚交周报',
      );
      await turnRepository.createTurn(turn);

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
            ),
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            toolAccess: ToolAccessSnapshot(
              definition: ToolDefinition(
                name: 'create_reminder',
                title: '创建提醒',
              ),
              executionDecision: ToolPolicyDecision.requireConfirmation,
              executionPolicyLabel: 'require_confirmation',
              isVisibleToPlanner: true,
            ),
            toolResult: null,
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(emitted.map((event) => event.eventType),
          contains(ChatEventType.assistantToolConfirmation));
      final confirmationEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.assistantToolConfirmation,
      );
      expect(confirmationEvent.payloadJson?['executionPolicy'], isNull);
      expect(
        confirmationEvent.payloadJson?['toolAccess']?['executionPolicy'],
        'require_confirmation',
      );
      expect((await turnRepository.getTurn(2))!.status,
          ChatTurnStatus.awaitingToolConfirmation);
    });

    test('fails turn when tool execution keeps failing beyond limit', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 3,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '连续调用失败',
      );
      await turnRepository.createTurn(turn);

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
            ),
          ),
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
            ),
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.failure,
              summary: '搜索失败',
              errorMessage: 'search_failed',
            ),
          ),
        ),
        limits:
            const AgentLoopLimits(maxIterations: 4, maxConsecutiveFailures: 1),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(emitted.map((event) => event.eventType),
          contains(ChatEventType.toolError));
      expect((await turnRepository.getTurn(3))!.status, ChatTurnStatus.failed);
    });

    test('resume after confirmation does not append duplicate started event',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 33,
        groupId: 1,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '确认后执行',
      );
      await turnRepository.createTurn(turn);

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '提醒已经创建',
            providerState: {'response_id': 'resp_after_confirm'},
            isTerminal: true,
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
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
              summary: '已创建提醒',
            ),
            executionStarted: true,
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .resumeAfterConfirmation(
            turnId: 33,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '请确认执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.where(
            (event) => event.eventType == ChatEventType.assistantToolCall),
        isEmpty,
      );
      expect(
        emitted.where((event) => event.eventType == ChatEventType.toolResult),
        hasLength(1),
      );
    });

    test(
        'continues loop after file tool failure and returns failure result to planner',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 301,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '读取不存在的文件后告诉我怎么处理',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _NativeDecisionPlannerService([
        const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              providerCallId: 'call_read_1',
              toolName: 'Read',
              arguments: {'file_path': 'missing.md'},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          providerState: {'response_id': 'resp_1'},
          isTerminal: false,
        ),
        const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '文件不存在，请先确认正确路径后我再继续。',
          diagnosticCode: 'planner_action_respond',
          providerState: {'response_id': 'resp_2'},
          isTerminal: true,
        ),
      ]);

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'Read',
              arguments: {'file_path': 'missing.md'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：读取文件',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'Read',
              status: ToolExecutionStatus.failure,
              summary: 'Read failed: file not found',
              data: {
                'filePath': 'agent/missing.md',
                'message':
                    'Read failed: file not found\n实际文件路径：agent/missing.md',
              },
              errorMessage: 'file_not_found',
            ),
          ),
        ),
        limits:
            const AgentLoopLimits(maxIterations: 4, maxConsecutiveFailures: 2),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(plannerService.nativeDecisionCalls, 2);
      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolError,
          ChatEventType.turnStatus,
          ChatEventType.finalAnswer,
        ]),
      );
      final toolErrorEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.toolError,
      );
      expect(toolErrorEvent.content, 'Read failed: file not found');
      expect(toolErrorEvent.status, 'file_not_found');
      expect(
        toolErrorEvent.payloadJson?['data'],
        containsPair('filePath', 'agent/missing.md'),
      );
      final step = (await stepRepository.listSteps(turnId)).single;
      expect(step.status, ChatTurnStepStatus.failed);
      expect(step.errorCode, 'file_not_found');
      final finalAnswerEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswerEvent.content, '文件不存在，请先确认正确路径后我再继续。');
      expect((await turnRepository.getTurn(turnId))!.status,
          ChatTurnStatus.completed);
    });

    test(
        'continues repeated retrieval steps based on loop state rather than planner patching',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 30,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续查数据库版本',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
            ),
            diagnosticCode: 'planner_action_call_tool',
          ),
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
            ),
            diagnosticCode: 'planner_action_call_tool',
          ),
          const AgentAction.respond(
            '两次检索后给出最终回答',
            diagnosticCode: 'planner_action_respond',
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '未命中相关聊天记录',
              data: {
                'query': '数据库版本',
                'matchCount': 0,
                'matches': [],
              },
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 5),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      final toolResults = emitted
          .where((event) => event.eventType == ChatEventType.toolResult)
          .toList(growable: false);
      expect(toolResults, hasLength(2));
      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.finalAnswer,
        ]),
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
    });

    test('allows an identical retrieval tool call in a later turn iteration',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 31,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续查 agent loop',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      final harness = TurnHarness(
        plannerService: AgentPlannerService(
          llm: _QueuedNativeDecisionLLM([
            const ModelTurnDecision(
              toolCalls: [
                ModelToolCall(
                  toolName: 'search_chat_history',
                  arguments: {'query': 'agent loop', 'maxResults': 5},
                  sequence: 1,
                ),
              ],
              assistantMessage: null,
              diagnosticCode: 'planner_action_call_tool',
              providerState: {},
              isTerminal: false,
            ),
            const ModelTurnDecision(
              toolCalls: [
                ModelToolCall(
                  toolName: 'search_chat_history',
                  arguments: {'query': 'agent loop', 'maxResults': 5},
                  sequence: 1,
                ),
              ],
              assistantMessage: null,
              diagnosticCode: 'planner_action_call_tool',
              providerState: {},
              isTerminal: false,
            ),
            const ModelTurnDecision(
              toolCalls: [],
              assistantMessage: '基于两次检索结果给出最终回答',
              diagnosticCode: 'planner_action_respond',
              providerState: {},
              isTerminal: true,
            ),
          ]),
          toolPolicyService: await _createToolPolicyService(),
          availableTools: const [
            ToolDefinition(
              name: 'search_chat_history',
              title: '搜索聊天记录',
              descriptionForModel: '当用户要求从历史记录找结论时使用。',
              argumentSchema: ToolArgumentSchema(
                properties: {
                  'query': ToolArgumentProperty.string(description: '查询词'),
                  'maxResults': ToolArgumentProperty.integer(description: '数量'),
                },
                required: ['query'],
              ),
            ),
          ],
        ),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': 'agent loop', 'maxResults': 5},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已执行：搜索历史记录',
              data: {
                'query': 'agent loop',
                'matchCount': 1,
              },
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      final toolResults = emitted
          .where((event) => event.eventType == ChatEventType.toolResult)
          .toList(growable: false);
      expect(toolResults, hasLength(2));
      expect(
        emitted.where((event) => event.eventType == ChatEventType.finalAnswer),
        isNotEmpty,
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
    });

    test(
        'resumes awaiting confirmation turn, executes tool, then completes with terminal answer',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 4,
        groupId: 1,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '提醒我明晚交周报',
      );
      await turnRepository.createTurn(turn);
      await eventRepository.appendToolConfirmation(
        turnId: 4,
        groupId: 1,
        toolName: 'create_reminder',
        arguments: const {'title': '交周报'},
        summary: '准备执行工具：创建提醒',
      );

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.respond('工具执行后给出最终回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
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
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .resumeAfterConfirmation(
            turnId: 4,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            config: ChatConfig(systemPrompt: ''),
            trustTool: true,
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.finalAnswer,
        ]),
      );
      final finalAnswerEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswerEvent.content, '工具执行后给出最终回答');
      expect(
          (await turnRepository.getTurn(4))!.status, ChatTurnStatus.completed);
    });

    test(
        'resumeAfterConfirmation clears awaiting state before final stop verification',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 40,
        groupId: 1,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '提醒我明早开会',
      );
      await turnRepository.createTurn(turn);
      await eventRepository.appendToolConfirmation(
        turnId: 40,
        groupId: 1,
        toolName: 'create_reminder',
        arguments: const {'title': '开会'},
        summary: '请确认执行工具：创建提醒',
      );

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.respond('工具执行后给出最终回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: TurnVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '开会'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：创建提醒',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'create_reminder',
              status: ToolExecutionStatus.success,
              summary: '已创建提醒：开会',
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 2),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .resumeAfterConfirmation(
            turnId: 40,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '开会'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '请确认执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        contains(ChatEventType.finalAnswer),
      );
      expect(
        (await turnRepository.getTurn(40))!.status,
        ChatTurnStatus.completed,
      );
    });

    test(
        'resumeAfterConfirmation persists providerCallId on tool result events for continuation pairing',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final llm = _NoopBaseLLM();
      final turn = ChatTurn(
        id: 401,
        groupId: 1,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '确认后继续',
      );
      await turnRepository.createTurn(turn);
      await eventRepository.appendToolConfirmation(
        turnId: 401,
        groupId: 1,
        toolName: 'create_reminder',
        arguments: const {'title': '开会'},
        summary: '请确认执行工具：创建提醒',
        payloadJson: const {
          'toolName': 'create_reminder',
          'arguments': {'title': '开会'},
          'status': 'awaitingConfirmation',
          'summary': '请确认执行工具：创建提醒',
          'requiresConfirmation': true,
          'providerCallId': 'call_reminder_1',
        },
      );

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.respond('工具执行后给出最终回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: TurnVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '开会'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：创建提醒',
              requiresConfirmation: false,
              providerCallId: 'call_reminder_1',
            ),
            toolResult: ToolResult(
              toolName: 'create_reminder',
              status: ToolExecutionStatus.success,
              summary: '已创建提醒：开会',
            ),
          ),
        ),
        sessionContextService: SessionContextService(
          chatTurnRepository: turnRepository,
          chatEventRepository: eventRepository,
          snapshotRepository: SessionContextSnapshotRepository(
            _NoopChatStorage(),
          ),
          contextProjector: SessionContextProjector(),
          tokenBudgetService: SessionTokenBudgetService(
            modelBudgetResolver: (_) => const SessionModelBudget(
              maxContextTokens: 10000,
              reservedOutputTokens: 1000,
              safetyMarginTokens: 500,
            ),
          ),
          summaryService: SessionSummaryService(
            summaryGenerator: (_) async => 'summary',
          ),
          chatService: ChatService(llm: llm),
        ),
        limits: const AgentLoopLimits(maxIterations: 2),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .resumeAfterConfirmation(
            turnId: 401,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '开会'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '请确认执行工具：创建提醒',
              requiresConfirmation: true,
              providerCallId: 'call_reminder_1',
            ),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      final resultEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.toolResult,
      );
      expect(resultEvent.payloadJson?['providerCallId'], 'call_reminder_1');
    });

    test('resumeAfterConfirmation completes the original pending turn step',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turn = ChatTurn(
        id: 41,
        groupId: 1,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '提醒我明早开会',
      );
      await turnRepository.createTurn(turn);
      await stepRepository.createStep(
        ChatTurnStep(
          id: 7,
          turnId: 41,
          stepIndex: 1,
          toolName: 'create_reminder',
          toolArgsJson: const {'title': '开会'},
          status: ChatTurnStepStatus.planned,
        ),
      );
      await eventRepository.appendToolConfirmation(
        turnId: 41,
        groupId: 1,
        toolName: 'create_reminder',
        arguments: const {'title': '开会'},
        summary: '请确认执行工具：创建提醒',
      );

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.respond('工具执行后给出最终回答'),
        ]),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: TurnVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '开会'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：创建提醒',
              requiresConfirmation: false,
              stepId: 7,
            ),
            toolResult: ToolResult(
              toolName: 'create_reminder',
              status: ToolExecutionStatus.success,
              summary: '已创建提醒：开会',
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 2),
        chatStorage: _NoopChatStorage(),
);

      await harness
          .resumeAfterConfirmation(
            turnId: 41,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '开会'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '请确认执行工具：创建提醒',
              requiresConfirmation: true,
              stepId: 7,
            ),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        (await stepRepository.getStep(7))!.status,
        ChatTurnStepStatus.completed,
      );
      expect(
        (await turnRepository.getTurn(41))!.status,
        ChatTurnStatus.completed,
      );
    });

    test(
        'resumeAfterConfirmation marks the pending step running before surfacing execution errors',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      await turnRepository.createTurn(
        ChatTurn(
          id: 47,
          groupId: 1,
          status: ChatTurnStatus.awaitingToolConfirmation,
          userInput: '提醒我同步异常',
        ),
      );
      await stepRepository.createStep(
        ChatTurnStep(
          id: 10,
          turnId: 47,
          stepIndex: 1,
          toolName: 'create_reminder',
          toolArgsJson: const {'title': '同步异常'},
          status: ChatTurnStepStatus.planned,
        ),
      );

      final harness = TurnHarness(
        plannerService: _FakePlannerService(const []),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _ThrowingToolCallService(
          invocation: const ToolInvocation(
            toolName: 'create_reminder',
            arguments: {'title': '同步异常'},
            status: ToolInvocationStatus.running,
            summary: '正在执行工具：创建提醒',
            requiresConfirmation: false,
            stepId: 10,
          ),
          error: StateError('resume_failed'),
        ),
        limits: const AgentLoopLimits(maxIterations: 2),
        chatStorage: _NoopChatStorage(),
);

      await expectLater(
        harness
            .resumeAfterConfirmation(
              turnId: 47,
              invocation: const ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '同步异常'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：创建提醒',
                requiresConfirmation: true,
                stepId: 10,
              ),
              config: ChatConfig(systemPrompt: ''),
            )
            .toList(),
        throwsA(isA<StateError>()),
      );

      expect(
        (await stepRepository.getStep(10))!.status,
        ChatTurnStepStatus.running,
      );
    });

    test(
        'resumeAfterConfirmation fails the turn when resumed tool returns no result at failure limit',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      await turnRepository.createTurn(
        ChatTurn(
          id: 48,
          groupId: 1,
          status: ChatTurnStatus.awaitingToolConfirmation,
          userInput: '提醒我同步异常',
        ),
      );
      await stepRepository.createStep(
        ChatTurnStep(
          id: 11,
          turnId: 48,
          stepIndex: 1,
          toolName: 'create_reminder',
          toolArgsJson: const {'title': '同步异常'},
          status: ChatTurnStepStatus.planned,
        ),
      );

      final harness = TurnHarness(
        plannerService: _FakePlannerService(const []),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '同步异常'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：创建提醒',
              requiresConfirmation: false,
              stepId: 11,
            ),
            toolResult: null,
          ),
        ),
        limits: const AgentLoopLimits(maxConsecutiveFailures: 1),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .resumeAfterConfirmation(
            turnId: 48,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '同步异常'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '请确认执行工具：创建提醒',
              requiresConfirmation: true,
              stepId: 11,
            ),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolError,
        ]),
      );
      expect(
        emitted
            .lastWhere((event) => event.eventType == ChatEventType.toolError)
            .content,
        'tool_execution_failed',
      );
      expect((await turnRepository.getTurn(48))!.status, ChatTurnStatus.failed);
      expect(
        (await turnRepository.getTurn(48))!.errorMessage,
        'tool_execution_failed',
      );
      expect((await stepRepository.getStep(11))!.status,
          ChatTurnStepStatus.failed);
      expect(
        (await stepRepository.getStep(11))!.errorCode,
        'tool_execution_failed',
      );
    });

    test('resumeAfterConfirmation throws when the turn does not exist',
        () async {
      final harness = TurnHarness(
        plannerService: _FakePlannerService(const []),
        turnRepository: _InMemoryChatTurnRepository(),
        eventRepository: _InMemoryChatEventRepository(),
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: _InMemoryChatEventRepository(),
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        chatStorage: _NoopChatStorage(),
);

      await expectLater(
        harness
            .resumeAfterConfirmation(
              turnId: 999,
              invocation: const ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': 'missing'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '请确认执行工具：创建提醒',
                requiresConfirmation: true,
              ),
              config: ChatConfig(systemPrompt: ''),
            )
            .toList(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Turn 999 not found'),
          ),
        ),
      );
    });

    test(
        'suspends turn for ask user question and emits assistant question prompt',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 42,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我设计存储方案',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                providerCallId: 'call_ask_1',
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
                sequence: 1,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_ask_1'},
            providerStyle: ChatTurnProviderStyle.openaiResponses,
            modelName: 'gpt-5.4',
            isTerminal: false,
          ),
        ]),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
          definitionsByName: const {
            'ask_user_question': ToolDefinition(
              name: 'ask_user_question',
              title: '向用户提问',
              runtimeKind: ToolRuntimeKind.userInteraction,
            ),
          },
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        contains(ChatEventType.assistantQuestionPrompt),
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.awaitingUserInteraction,
      );
      final step = (await stepRepository.listSteps(turnId)).single;
      expect(step.providerCallId, 'call_ask_1');
      expect(step.providerResponseId, 'resp_ask_1');
    });

    test(
        'resumeAfterQuestionAnswered records interaction result, completes step, and continues loop',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 43,
          groupId: 1,
          status: ChatTurnStatus.awaitingUserInteraction,
          userInput: '帮我设计存储方案',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
          providerStateJson: const {'response_id': 'resp_ask_1'},
        ),
      );
      await stepRepository.createStep(
        ChatTurnStep(
          id: 9,
          turnId: turnId,
          stepIndex: 1,
          providerResponseId: 'resp_ask_1',
          providerCallId: 'call_ask_1',
          toolName: 'ask_user_question',
          toolArgsJson: const {
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
          status: ChatTurnStepStatus.planned,
        ),
      );

      final toolCallService = _FakeToolCallService(
        executeResult: const ToolPreparationResult.noTool(),
      );
      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '建议先用 SQLite。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'response_id': 'resp_ask_2'},
            providerStyle: ChatTurnProviderStyle.openaiResponses,
            modelName: 'gpt-5.4',
            isTerminal: true,
          ),
        ]),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .resumeAfterQuestionAnswered(
            turnId: turnId,
            request: AskUserQuestionRequest.fromJson(const {
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
              'agentTurnId': 43,
              'stepId': 9,
              'providerCallId': 'call_ask_1',
            }),
            response: AskUserQuestionResponse.fromJson(const {
              'answersByQuestionId': {
                'storage_layer': 'SQLite',
              },
              'selectedOptionLabelsByQuestionId': {
                'storage_layer': ['SQLite'],
              },
              'freeTextAnswersByQuestionId': {},
            }),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(toolCallService.executeInvocationCount, 0);
      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userInteractionResult,
          ChatEventType.finalAnswer,
        ]),
      );
      final finalAnswerEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswerEvent.content, '建议先用 SQLite。');
      final step = (await stepRepository.getStep(9))!;
      expect(step.status, ChatTurnStepStatus.completed);
      expect(step.providerCallId, 'call_ask_1');
      expect(
        step.resultJson?['answersByQuestionId'],
        containsPair('storage_layer', 'SQLite'),
      );
      expect(
        step.resultJson?['transcriptContent'],
        'User answered AskUserQuestion:\n- Storage: SQLite',
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
    });

    test(
        'fails with planner_no_terminal_decision on a later loop after tool execution',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 44,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '先查资料，再继续',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _RecordingDecisionPlannerService([
        const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          diagnosticCode: 'planner_action_call_tool',
          providerState: {'response_id': 'resp_loop_1'},
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
          isTerminal: false,
        ),
        const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '我还需要再想一想。',
          diagnosticCode: 'planner_needs_follow_up',
          providerState: {'response_id': 'resp_loop_2'},
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
          isTerminal: false,
        ),
      ]);

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _SequencedToolCallService([
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
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
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(plannerService.planCalls, 2);
      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantPlannerMessage,
          ChatEventType.turnStatus,
        ]),
      );
      expect(
        emitted.where((event) => event.eventType == ChatEventType.finalAnswer),
        isEmpty,
      );
      expect(
        emitted
            .lastWhere((event) => event.eventType == ChatEventType.turnStatus)
            .content,
        'planner_no_terminal_decision',
      );

      final persistedTurn = (await turnRepository.getTurn(turnId))!;
      expect(persistedTurn.status, ChatTurnStatus.failed);
      expect(persistedTurn.errorMessage, 'planner_no_terminal_decision');
    });

    test(
        'builds planner messages from session context on later loop iterations',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final sessionContextService = _StubSessionContextService();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 45,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '先查版本，再给我结论',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _RecordingDecisionPlannerService([
        const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '版本'},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          diagnosticCode: 'planner_action_call_tool',
          providerState: {'response_id': 'resp_ctx_1'},
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
          isTerminal: false,
        ),
        const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '数据库版本是 7。',
          diagnosticCode: 'planner_action_respond',
          providerState: {'response_id': 'resp_ctx_2'},
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
          isTerminal: true,
        ),
      ]);

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _SequencedToolCallService([
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已执行：搜索历史记录',
              data: {
                'query': '版本',
                'matchCount': 1,
              },
            ),
          ),
        ]),
        sessionContextService: sessionContextService,
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(plannerService.planCalls, 2);
      expect(sessionContextService.calls, hasLength(2));
      expect(
        sessionContextService.calls
            .map((call) => call.currentTurnTranscript.length)
            .toList(growable: false),
        orderedEquals([1, 5]),
      );
      expect(
        plannerService.capturedPlannerMessages
            .map((messages) => messages?.single.text)
            .toList(growable: false),
        ['ctx-call-1', 'ctx-call-2'],
      );
      expect(
        emitted
            .lastWhere((event) => event.eventType == ChatEventType.finalAnswer)
            .content,
        '数据库版本是 7。',
      );
    });

    test(
        'preserves prior provider style and model when later loop only refreshes provider state',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 46,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '查完后直接告诉我结果',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _RecordingDecisionPlannerService(
        [
          const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_chat_history',
                arguments: {'query': '结果'},
                sequence: 1,
              ),
            ],
            assistantMessage: null,
            diagnosticCode: 'planner_action_call_tool',
            providerState: {'response_id': 'resp_state_1'},
            providerStyle: ChatTurnProviderStyle.openaiResponses,
            modelName: 'gpt-5.4',
            isTerminal: false,
          ),
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '已经确认结果。',
            diagnosticCode: 'planner_action_respond',
            providerState: {'message_id': 'msg_state_2'},
            isTerminal: true,
          ),
        ],
        fillMissingRuntimeMetadata: false,
      );

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _SequencedToolCallService([
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '结果'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已执行：搜索历史记录',
              data: {
                'query': '结果',
                'matchCount': 1,
              },
            ),
          ),
        ]),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      final finalAnswerEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswerEvent.content, '已经确认结果。');

      final persistedTurn = (await turnRepository.getTurn(turnId))!;
      expect(
        persistedTurn.providerStyle,
        ChatTurnProviderStyle.openaiResponses,
      );
      expect(persistedTurn.modelName, 'gpt-5.4');
      expect(
        persistedTurn.providerStateJson,
        equals(const {'message_id': 'msg_state_2'}),
      );
    });

    test(
        'integrates planner session context and responses continuation across a multi-round loop',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final previousTurnId = await turnRepository.createTurn(
        ChatTurn(
          id: 60,
          groupId: 1,
          status: ChatTurnStatus.completed,
          userInput: '上一轮确认数据库版本',
        ),
      );
      await eventRepository.appendAssistantPlannerMessage(
        turnId: previousTurnId,
        groupId: 1,
        content: '历史结论：数据库版本线索在发布记录里。',
      );

      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 61,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续确认版本并整理结果',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final llm = _AssertingLoopPlannerLLM();
      final harness = TurnHarness(
        plannerService: AgentPlannerService(
          llm: llm,
          toolPolicyService: await _createToolPolicyService(),
          availableTools: const [
            ToolDefinition(
              name: 'search_chat_history',
              title: '搜索聊天记录',
              descriptionForModel: '当需要从历史记录确认事实时使用。',
              argumentSchema: ToolArgumentSchema(
                properties: {
                  'query': ToolArgumentProperty.string(description: '查询词'),
                },
                required: ['query'],
              ),
            ),
            ToolDefinition(
              name: 'Write',
              title: '写入文件',
              descriptionForModel: '当需要把结果写入文件时使用。',
              argumentSchema: ToolArgumentSchema(
                properties: {
                  'file_path': ToolArgumentProperty.string(description: '文件路径'),
                  'content': ToolArgumentProperty.string(description: '内容'),
                },
                required: ['file_path', 'content'],
              ),
            ),
          ],
        ),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _SequencedToolCallService([
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已执行：搜索历史记录',
              data: {
                'query': '数据库版本',
                'matchCount': 1,
                'matches': [
                  {'text': '数据库版本是 7'},
                ],
              },
            ),
          ),
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'Write',
              arguments: {
                'file_path': 'notes/version.md',
                'content': '数据库版本是 7',
              },
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：写入文件',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'Write',
              status: ToolExecutionStatus.success,
              summary: '已写入文件：notes/version.md',
              data: {
                'filePath': 'notes/version.md',
              },
            ),
          ),
        ]),
        sessionContextService: SessionContextService(
          chatTurnRepository: turnRepository,
          chatEventRepository: eventRepository,
          snapshotRepository: SessionContextSnapshotRepository(
            _NoopChatStorage(),
          ),
          contextProjector: SessionContextProjector(),
          tokenBudgetService: SessionTokenBudgetService(
            modelBudgetResolver: (_) => const SessionModelBudget(
              maxContextTokens: 10000,
              reservedOutputTokens: 1000,
              safetyMarginTokens: 500,
            ),
          ),
          summaryService: SessionSummaryService(
            summaryGenerator: (_) async => 'summary',
          ),
          chatService: ChatService(llm: llm),
        ),
        limits: const AgentLoopLimits(maxIterations: 5),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(llm.planCalls, 3);
      expect(
        emitted.where((event) => event.eventType == ChatEventType.toolResult),
        hasLength(2),
      );
      expect(
        emitted
            .lastWhere((event) => event.eventType == ChatEventType.finalAnswer)
            .content,
        '数据库版本已确认，并已记录到 notes/version.md。',
      );

      final persistedSteps = await stepRepository.listSteps(turnId);
      expect(persistedSteps, hasLength(2));
      expect(
        persistedSteps.map((step) => step.providerResponseId).toList(),
        ['resp_1', 'resp_2'],
      );
      expect(
        persistedSteps.map((step) => step.providerCallId).toList(),
        ['call_1', 'call_2'],
      );
      expect(
        persistedSteps
            .every((step) => step.status == ChatTurnStepStatus.completed),
        isTrue,
      );

      final persistedTurn = (await turnRepository.getTurn(turnId))!;
      expect(persistedTurn.status, ChatTurnStatus.completed);
      expect(
        persistedTurn.providerStateJson,
        equals(const {'response_id': 'resp_3'}),
      );
      expect(
          persistedTurn.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(persistedTurn.modelName, 'gpt-5.4');
    });

    test(
        'integrates ask-user resume with planner continuation items and final response',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final llm = _AssertingQuestionLoopPlannerLLM();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 62,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我确定存储方案',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final harness = TurnHarness(
        plannerService: AgentPlannerService(
          llm: llm,
          toolPolicyService: await _createToolPolicyService(),
          availableTools: const [
            ToolDefinition(
              name: 'ask_user_question',
              title: '向用户提问',
              descriptionForModel: '当需要用户补充关键决策时使用。',
              runtimeKind: ToolRuntimeKind.userInteraction,
              argumentSchema: ToolArgumentSchema(
                properties: {
                  'questions': ToolArgumentProperty(
                    type: 'array',
                    description: '问题列表',
                  ),
                },
                required: ['questions'],
              ),
            ),
          ],
        ),
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
          definitionsByName: const {
            'ask_user_question': ToolDefinition(
              name: 'ask_user_question',
              title: '向用户提问',
              runtimeKind: ToolRuntimeKind.userInteraction,
            ),
          },
        ),
        sessionContextService: SessionContextService(
          chatTurnRepository: turnRepository,
          chatEventRepository: eventRepository,
          snapshotRepository: SessionContextSnapshotRepository(
            _NoopChatStorage(),
          ),
          contextProjector: SessionContextProjector(),
          tokenBudgetService: SessionTokenBudgetService(
            modelBudgetResolver: (_) => const SessionModelBudget(
              maxContextTokens: 10000,
              reservedOutputTokens: 1000,
              safetyMarginTokens: 500,
            ),
          ),
          summaryService: SessionSummaryService(
            summaryGenerator: (_) async => 'summary',
          ),
          chatService: ChatService(llm: llm),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final suspended = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(llm.planCalls, 1);
      expect(
        suspended.map((event) => event.eventType),
        contains(ChatEventType.assistantQuestionPrompt),
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.awaitingUserInteraction,
      );

      final step = (await stepRepository.listSteps(turnId)).single;
      final resumed = await harness
          .resumeAfterQuestionAnswered(
            turnId: turnId,
            request: AskUserQuestionRequest.fromJson({
              'questions': const [
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
              'agentTurnId': turnId,
              'stepId': step.id,
              'providerCallId': 'ask_call_1',
            }),
            response: AskUserQuestionResponse.fromJson(const {
              'answersByQuestionId': {
                'storage_layer': 'SQLite',
              },
              'selectedOptionLabelsByQuestionId': {
                'storage_layer': ['SQLite'],
              },
              'freeTextAnswersByQuestionId': {},
            }),
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(llm.planCalls, 2);
      expect(
        resumed.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userInteractionResult,
          ChatEventType.finalAnswer,
        ]),
      );
      expect(
        resumed
            .lastWhere((event) => event.eventType == ChatEventType.finalAnswer)
            .content,
        '建议采用 SQLite 作为当前方案。',
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
      expect(
        (await turnRepository.getTurn(turnId))!.providerStateJson,
        equals(const {'response_id': 'resp_ask_2'}),
      );
      expect((await stepRepository.getStep(step.id!))!.status,
          ChatTurnStepStatus.completed);
    });

    test(
        'stops turn with max_iterations_reached when stop verifier keeps rejecting',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 5,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '继续完善这个回答直到确认完成',
      );
      await turnRepository.createTurn(turn);

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.respond('第一次回答'),
          const AgentAction.respond('第二次回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _NeverStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxIterations: 1),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.turnStatus,
          ChatEventType.turnStatus,
        ]),
      );
      final statusEvents = emitted
          .where((event) => event.eventType == ChatEventType.turnStatus)
          .toList(growable: false);
      expect(statusEvents.map((event) => event.content), [
        'planner_action_respond',
        'needs_more_work',
        'max_iterations_reached',
      ]);
      expect(
        emitted.last,
        isA<ChatEvent>()
            .having((event) => event.eventType, 'eventType',
                ChatEventType.turnStatus)
            .having(
                (event) => event.content, 'content', 'max_iterations_reached'),
      );
      expect((await turnRepository.getTurn(5))!.status, ChatTurnStatus.failed);
      expect((await turnRepository.getTurn(5))!.errorMessage,
          'max_iterations_reached');
    });

    test('default AgentLoopLimits does not block high-count turns', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      await turnRepository.createTurn(
        ChatTurn(
          id: 50,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续总结当前结果',
          iterationCount: 999,
          toolCallCount: 999,
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          updatedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      );
      final turn = (await turnRepository.getTurn(50))!;

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService([
          const ModelTurnDecision(
            toolCalls: [],
            assistantMessage: '继续基于当前上下文给出结果',
            diagnosticCode: 'planner_action_respond',
            providerState: {},
            isTerminal: true,
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.finalAnswer,
        ]),
      );
      expect(emitted.last.content, '继续基于当前上下文给出结果');
      expect(
          (await turnRepository.getTurn(50))!.status, ChatTurnStatus.completed);
    });

    test('stops turn with max_tool_calls_reached before planner continues',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      await turnRepository.createTurn(
        ChatTurn(
          id: 51,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续搜',
          toolCallCount: 3,
        ),
      );
      final turn = (await turnRepository.getTurn(51))!;

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService(const []),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxToolCallsPerTurn: 3),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        [ChatEventType.userMessage, ChatEventType.turnStatus],
      );
      expect(emitted.last.content, 'max_tool_calls_reached');
      expect((await turnRepository.getTurn(51))!.status, ChatTurnStatus.failed);
      expect(
        (await turnRepository.getTurn(51))!.errorMessage,
        'max_tool_calls_reached',
      );
    });

    test('stops turn with max_duration_reached before planner continues',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      await turnRepository.createTurn(
        ChatTurn(
          id: 52,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续搜',
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      );
      final turn = (await turnRepository.getTurn(52))!;

      final harness = TurnHarness(
        plannerService: _NativeDecisionPlannerService(const []),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxDuration: Duration(minutes: 1)),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        [ChatEventType.userMessage, ChatEventType.turnStatus],
      );
      expect(emitted.last.content, 'max_duration_reached');
      expect((await turnRepository.getTurn(52))!.status, ChatTurnStatus.failed);
      expect(
        (await turnRepository.getTurn(52))!.errorMessage,
        'max_duration_reached',
      );
    });

    test('pauses on a later tool after an earlier tool already succeeded',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 6,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '先搜数据库版本，再帮我创建提醒',
      );
      await turnRepository.createTurn(turn);

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
            ),
          ),
          const AgentAction.callTool(
            ToolCall(
              toolName: 'create_reminder',
              arguments: {'title': '同步 schema 变更'},
            ),
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _SequencedToolCallService([
          ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '数据库版本是 7',
            ),
          ),
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '同步 schema 变更'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            toolResult: null,
          ),
        ]),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantToolCall,
          ChatEventType.assistantToolConfirmation,
        ]),
      );
      expect((await turnRepository.getTurn(6))!.status,
          ChatTurnStatus.awaitingToolConfirmation);
      expect((await turnRepository.getTurn(6))!.toolCallCount, 1);
    });

    test(
        'records planner request failure as turn status and surfaces failure message as final answer',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 7,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '帮我联网查最新进展',
      );
      await turnRepository.createTurn(turn);

      final harness = TurnHarness(
        plannerService: _FakePlannerService([
          const AgentAction.respond(
            '抱歉，我暂时无法规划下一步动作，请直接重试。',
            diagnosticCode: 'planner_request_failed',
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.finalAnswer,
        ]),
      );
      expect(
        emitted
            .where((event) => event.eventType == ChatEventType.turnStatus)
            .map((event) => event.content),
        contains('planner_request_failed'),
      );
      expect(
        emitted
            .where((event) => event.eventType == ChatEventType.finalAnswer)
            .map((event) => event.content),
        contains('抱歉，我暂时无法规划下一步动作，请直接重试。'),
      );
    });

    test(
        'passes compact tool summary into the next planner iteration transcript',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 8,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我联网搜索 Claude 最新进展',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _FakePlannerService([
        const AgentAction.callTool(
          ToolCall(
            toolName: 'web_search',
            arguments: {'query': 'Claude latest news'},
          ),
          diagnosticCode: 'planner_action_call_tool',
        ),
        const AgentAction.respond(
          '基于搜索结果总结',
          diagnosticCode: 'planner_action_respond',
        ),
      ]);

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'Claude latest news'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：联网搜索',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'web_search',
              status: ToolExecutionStatus.success,
              summary: '已执行联网搜索',
              data: {
                'query': 'Claude latest news',
                'results': [
                  {
                    'title': 'Claude 3.7 Sonnet announced',
                    'snippet': 'Anthropic introduced a hybrid reasoning model.',
                    'url': 'https://example.com/claude-3-7',
                    'source': 'example.com',
                  },
                ],
              },
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(plannerService.capturedTranscripts, hasLength(2));
      final toolResultContent = plannerService.capturedTranscripts[1]
          .where((event) => event.eventType == ChatEventType.toolResult)
          .single
          .content;
      expect(toolResultContent, '已执行联网搜索');
      expect(toolResultContent, isNot(contains('Claude 3.7 Sonnet announced')));
      expect(
        toolResultContent,
        isNot(contains('Anthropic introduced a hybrid reasoning model.')),
      );
    });

    test(
        'keeps tool-result transcript summary compact even when payload has model context',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 81,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续编辑爱好笔记',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _FakePlannerService([
        const AgentAction.callTool(
          ToolCall(
            toolName: 'Edit',
            arguments: {
              'file_path': 'my_hobbies.md',
              'old_string': '篮球',
              'new_string': '篮球\n游戏',
            },
          ),
          diagnosticCode: 'planner_action_call_tool',
        ),
        const AgentAction.respond(
          '编辑完成',
          diagnosticCode: 'planner_action_respond',
        ),
      ]);

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'Edit',
              arguments: {
                'file_path': 'my_hobbies.md',
                'old_string': '篮球',
                'new_string': '篮球\n游戏',
              },
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：编辑文件',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'Edit',
              status: ToolExecutionStatus.success,
              summary: '已编辑文件：my_hobbies.md',
              data: {
                'filePath': 'agent/my_hobbies.md',
                'message': '已编辑文件：agent/my_hobbies.md',
              },
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      final toolResultContent = plannerService.capturedTranscripts[1]
          .where((event) => event.eventType == ChatEventType.toolResult)
          .single
          .content;
      expect(
        toolResultContent,
        '已编辑文件：my_hobbies.md',
      );
    });

    test(
        'records intermediate planner assistant text before executing provider-native tool calls',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 8,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查数据库版本',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _NativeDecisionPlannerService([
        const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              providerCallId: 'call_1',
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              sequence: 1,
            ),
          ],
          assistantMessage: '我先查一下数据库版本。',
          providerState: {'response_id': 'resp_1'},
          isTerminal: false,
        ),
        const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '我已经拿到结果了，开始整理最终答复。',
          providerState: {'response_id': 'resp_2'},
          isTerminal: true,
        ),
      ]);
      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已找到数据库版本是 7',
              data: {'query': '数据库版本', 'matchCount': 1},
            ),
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantPlannerMessage,
          ChatEventType.turnStatus,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
        ]),
      );
      final plannerMessage = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.assistantPlannerMessage,
      );
      expect(plannerMessage.content, '我先查一下数据库版本。');
      final toolCallIndex = emitted.indexWhere(
        (event) => event.eventType == ChatEventType.assistantToolCall,
      );
      final plannerMessageIndex = emitted.indexWhere(
        (event) => event.eventType == ChatEventType.assistantPlannerMessage,
      );
      expect(plannerMessageIndex, lessThan(toolCallIndex));
    });

    test(
        'executes multiple provider-native tool calls and completes without extra final-answer synthesis',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 9,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '先从聊天记录里找出数据库版本和发版时间，保存成笔记，再提醒我今晚 8 点同步给测试同学',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final plannerService = _NativeDecisionPlannerService([
        const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              providerCallId: 'call_1',
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本 发版时间'},
              sequence: 1,
            ),
            ModelToolCall(
              providerCallId: 'call_2',
              toolName: 'Write',
              arguments: {
                'file_path': 'notes/db-version.md',
                'content': '数据库版本 7，发版时间 2026-04-12 10:00',
              },
              sequence: 2,
            ),
            ModelToolCall(
              providerCallId: 'call_3',
              toolName: 'create_reminder',
              arguments: {
                'title': '同步数据库版本确认给测试同学',
                'dueAt': '2026-04-13T20:00:00+08:00',
              },
              sequence: 3,
            ),
          ],
          assistantMessage: null,
          providerState: {'response_id': 'resp_1'},
          isTerminal: false,
        ),
        const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '全部步骤已完成，请整理最终答复',
          providerState: {'response_id': 'resp_2'},
          isTerminal: true,
        ),
      ]);
      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        toolCallService: _SequencedToolCallService([
          ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本 发版时间'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已执行：搜索历史记录',
              data: {
                'query': '数据库版本 发版时间',
                'matchCount': 1,
                'matches': [
                  {
                    'text': '数据库版本是 7，发版时间是 2026-04-12 10:00',
                    'role': 'assistant',
                    'timestamp': '2026-04-12T10:00:00+08:00',
                  },
                ],
              },
            ),
          ),
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'Write',
              arguments: {
                'file_path': 'notes/db-version.md',
                'content': '数据库版本 7，发版时间 2026-04-12 10:00',
              },
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：写入文件',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'Write',
              status: ToolExecutionStatus.success,
              summary: '已写入文件：notes/db-version.md',
              data: {
                'filePath': 'notes/db-version.md',
              },
            ),
          ),
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'create_reminder',
              arguments: {
                'title': '同步数据库版本确认给测试同学',
                'dueAt': '2026-04-13T20:00:00+08:00',
              },
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：创建提醒',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'create_reminder',
              status: ToolExecutionStatus.success,
              summary: '已创建提醒：今晚 8 点同步给测试同学',
              data: {
                'title': '同步数据库版本确认给测试同学',
                'dueAt': '2026-04-13T20:00:00+08:00',
              },
            ),
          ),
        ]),
        limits: const AgentLoopLimits(maxIterations: 4),
        chatStorage: _NoopChatStorage(),
);

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(systemPrompt: ''),
          )
          .toList();

      expect(plannerService.nativeDecisionCalls, 2);
      final toolResults = emitted
          .where((event) => event.eventType == ChatEventType.toolResult)
          .toList(growable: false);
      expect(toolResults, hasLength(3));
      expect(toolResults.map((event) => event.content), [
        '已执行：搜索历史记录',
        '已写入文件：notes/db-version.md',
        '已创建提醒：今晚 8 点同步给测试同学',
      ]);
      expect(
        toolResults.map((event) => event.content).join('\n'),
        isNot(contains('命中历史消息')),
      );

      final persistedSteps = await stepRepository.listSteps(turnId);
      expect(persistedSteps, hasLength(3));
      expect(
        persistedSteps
            .map((step) => step.providerCallId)
            .toList(growable: false),
        ['call_1', 'call_2', 'call_3'],
      );
      expect(
        persistedSteps.map((step) => step.toolName).toList(growable: false),
        ['search_chat_history', 'Write', 'create_reminder'],
      );
      expect(
        toolResults
            .map((event) => event.payloadJson?['providerCallId'])
            .toList(growable: false),
        ['call_1', 'call_2', 'call_3'],
      );

      final finalAnswerEvent = emitted.firstWhere(
        (event) => event.eventType == ChatEventType.finalAnswer,
      );
      expect(finalAnswerEvent.content, '全部步骤已完成，请整理最终答复');

      final persistedTurn = (await turnRepository.getTurn(turnId))!;
      expect(
        persistedTurn.providerStyle,
        ChatTurnProviderStyle.openaiResponses,
      );
      expect(persistedTurn.modelName, 'gpt-5.4');
      expect(
        persistedTurn.providerStateJson,
        containsPair('response_id', 'resp_2'),
      );
    });
  });
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

class _FakePlannerService extends AgentPlannerService {
  final Queue<AgentAction> actions;
  final List<List<ChatEvent>> capturedTranscripts = [];

  _FakePlannerService(List<AgentAction> actions)
      : actions = Queue<AgentAction>.from(actions),
        super(llm: _NoopBaseLLM());

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
    capturedTranscripts.add(List<ChatEvent>.from(transcript));
    return _decisionFromAction(actions.removeFirst());
  }
}

class _NativeDecisionPlannerService extends AgentPlannerService {
  final Queue<ModelTurnDecision> decisions;
  int nativeDecisionCalls = 0;

  _NativeDecisionPlannerService(List<ModelTurnDecision> decisions)
      : decisions = Queue<ModelTurnDecision>.from(decisions),
        super(llm: _NoopBaseLLM());

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
    nativeDecisionCalls += 1;
    final decision = decisions.removeFirst();
    return decision.copyWith(
      providerStyle:
          decision.providerStyle ?? ChatTurnProviderStyle.openaiResponses,
      modelName: decision.modelName ?? 'gpt-5.4',
    );
  }
}

class _RecordingDecisionPlannerService extends AgentPlannerService {
  final Queue<ModelTurnDecision> decisions;
  final bool fillMissingRuntimeMetadata;
  final List<List<ChatMessage>?> capturedPlannerMessages = [];
  int planCalls = 0;

  _RecordingDecisionPlannerService(
    List<ModelTurnDecision> decisions, {
    this.fillMissingRuntimeMetadata = true,
  })  : decisions = Queue<ModelTurnDecision>.from(decisions),
        super(llm: _NoopBaseLLM());

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
    planCalls += 1;
    capturedPlannerMessages.add(
      carriers.isEmpty ? null : [for (final c in carriers) if (c is SyntheticCarrier) ChatMessage(text: c.content, role: c.role == SyntheticRole.user ? MessageRole.user : c.role == SyntheticRole.system ? MessageRole.system : MessageRole.user) else if (c is RawAssistantCarrier) ChatMessage(text: (c.rawJson['content'] as String?) ?? '', role: MessageRole.assistant)],
    );
    final decision = decisions.removeFirst();
    if (!fillMissingRuntimeMetadata) {
      return decision;
    }
    return decision.copyWith(
      providerStyle:
          decision.providerStyle ?? ChatTurnProviderStyle.openaiResponses,
      modelName: decision.modelName ?? 'gpt-5.4',
    );
  }
}

class _QueuedNativeDecisionLLM implements BaseLLM {
  final Queue<ModelTurnDecision> decisions;

  _QueuedNativeDecisionLLM(List<ModelTurnDecision> decisions)
      : decisions = Queue<ModelTurnDecision>.from(decisions);

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'queued-native-decision';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    if (decisions.isEmpty) {
      throw StateError('No more queued native decisions');
    }
    return decisions.removeFirst();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';
}

class _AssertingLoopPlannerLLM implements BaseLLM {
  int planCalls = 0;

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
    planCalls += 1;
    final joinedText = carriers
        .map((c) => c is SyntheticCarrier
            ? c.content
            : c is RawAssistantCarrier
                ? ((c.rawJson['content'] as String?) ?? '')
                : '')
        .join('\n');

    if (planCalls == 1) {
      expect(joinedText, contains('历史结论：数据库版本线索在发布记录里。'));
      expect(joinedText, contains('继续确认版本并整理结果'));
      expect(
        availableTools.map((tool) => tool.name).toList(),
        containsAll(['search_chat_history', 'Write']),
      );
      return const ModelTurnDecision(
        toolCalls: [
          ModelToolCall(
            providerCallId: 'call_1',
            toolName: 'search_chat_history',
            arguments: {'query': '数据库版本'},
            sequence: 1,
          ),
        ],
        assistantMessage: '我先检索历史记录。',
        diagnosticCode: 'planner_action_call_tool',
        providerState: {'response_id': 'resp_1'},
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        modelName: 'gpt-5.4',
        isTerminal: false,
      );
    }

    if (planCalls == 2) {
      expect(joinedText, contains('我先检索历史记录。'));
      expect(joinedText, contains('search_chat_history'));
      expect(joinedText, contains('数据库版本'));
      expect(joinedText, contains('search_chat_history query: 数据库版本'));
      expect(joinedText, contains('1. 数据库版本是 7'));
      return const ModelTurnDecision(
        toolCalls: [
          ModelToolCall(
            providerCallId: 'call_2',
            toolName: 'Write',
            arguments: {
              'file_path': 'notes/version.md',
              'content': '数据库版本是 7',
            },
            sequence: 1,
          ),
        ],
        assistantMessage: '我把确认结果写入文件。',
        diagnosticCode: 'planner_action_call_tool',
        providerState: {'response_id': 'resp_2'},
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        modelName: 'gpt-5.4',
        isTerminal: false,
      );
    }

    expect(planCalls, 3);
    expect(joinedText, contains('我把确认结果写入文件。'));
    expect(joinedText, contains('Write'));
    expect(joinedText, contains('notes/version.md'));
    expect(joinedText, contains('Write path: notes/version.md'));
    return const ModelTurnDecision(
      toolCalls: [],
      assistantMessage: '数据库版本已确认，并已记录到 notes/version.md。',
      diagnosticCode: 'planner_action_respond',
      providerState: {'response_id': 'resp_3'},
      providerStyle: ChatTurnProviderStyle.openaiResponses,
      modelName: 'gpt-5.4',
      isTerminal: true,
    );
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';
}

class _AssertingQuestionLoopPlannerLLM implements BaseLLM {
  int planCalls = 0;

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
    planCalls += 1;
    final joinedText = carriers
        .map((c) => c is SyntheticCarrier
            ? c.content
            : c is RawAssistantCarrier
                ? ((c.rawJson['content'] as String?) ?? '')
                : '')
        .join('\n');

    if (planCalls == 1) {
      expect(joinedText, contains('帮我确定存储方案'));
      expect(availableTools.map((tool) => tool.name),
          contains('ask_user_question'));
      return const ModelTurnDecision(
        toolCalls: [
          ModelToolCall(
            providerCallId: 'ask_call_1',
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
            sequence: 1,
          ),
        ],
        assistantMessage: null,
        diagnosticCode: 'planner_action_call_tool',
        providerState: {'response_id': 'resp_ask_1'},
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        modelName: 'gpt-5.4',
        isTerminal: false,
      );
    }

    expect(planCalls, 2);
    expect(joinedText, contains('Storage: SQLite'));
    expect(joinedText, contains('SQLite'));
    return const ModelTurnDecision(
      toolCalls: [],
      assistantMessage: '建议采用 SQLite 作为当前方案。',
      diagnosticCode: 'planner_action_respond',
      providerState: {'response_id': 'resp_ask_2'},
      providerStyle: ChatTurnProviderStyle.openaiResponses,
      modelName: 'gpt-5.4',
      isTerminal: true,
    );
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';
}

ModelTurnDecision _decisionFromAction(AgentAction action) {
  if (action.type == AgentActionType.callTool && action.toolCall != null) {
    return ModelTurnDecision(
      toolCalls: [
        ModelToolCall(
          toolName: action.toolCall!.toolName,
          arguments: action.toolCall!.arguments,
          sequence: 1,
        ),
      ],
      assistantMessage: null,
      diagnosticCode: action.diagnosticCode ?? 'planner_action_call_tool',
      providerState: const {},
      providerStyle: null,
      modelName: null,
      isTerminal: false,
    );
  }

  return ModelTurnDecision(
    toolCalls: const [],
    assistantMessage: action.response,
    diagnosticCode: action.diagnosticCode ?? 'planner_action_respond',
    providerState: const {},
    providerStyle: null,
    modelName: null,
    isTerminal: true,
  );
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
    return const StopVerificationResult(canStop: true, reason: 'done');
  }
}

class _NeverStopVerifier extends TurnVerifier {
  @override
  Future<StopVerificationResult> verifyCanStop({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    List<ChatTurnStep> steps = const [],
    required String latestAssistantText,
    required AgentLoopLimits limits,
  }) async {
    return const StopVerificationResult(
      canStop: false,
      reason: 'needs_more_work',
    );
  }
}

class _FakeToolCallService extends ToolCallService {
  final ToolPreparationResult executeResult;
  final Map<String, ToolDefinition> definitionsByName;
  int executeInvocationCount = 0;

  _FakeToolCallService({
    required this.executeResult,
    this.definitionsByName = const {},
  }) : super(
          toolExecutor: ToolExecutor(chatStorage: _NoopChatStorage()),
        );

  @override
  ToolDefinition? findDefinition(String toolName) {
    return definitionsByName[toolName] ?? super.findDefinition(toolName);
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
    if (onExecutionStarted != null && executeResult.executionStarted) {
      await onExecutionStarted(
        invocation: executeResult.toolInvocation ?? invocation,
        toolAccess: executeResult.toolAccess ??
            const ToolAccessSnapshot(
              definition: ToolDefinition(
                name: 'fake_tool',
                title: 'fake_tool',
              ),
              executionDecision: ToolPolicyDecision.autoRun,
              executionPolicyLabel: 'auto_run',
              isVisibleToPlanner: true,
            ),
      );
    }
    executeInvocationCount += 1;
    return executeResult;
  }
}

class _SequencedToolCallService extends ToolCallService {
  final Queue<ToolPreparationResult> executeResults;

  _SequencedToolCallService(List<ToolPreparationResult> executeResults)
      : executeResults = Queue<ToolPreparationResult>.from(executeResults),
        super(
          toolExecutor: ToolExecutor(chatStorage: _NoopChatStorage()),
        );

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    List<ChatEvent> currentTurnEvents = const <ChatEvent>[],
    ToolExecutionStartedCallback? onExecutionStarted,
  }) async {
    final result = executeResults.removeFirst();
    if (onExecutionStarted != null && result.executionStarted) {
      await onExecutionStarted(
        invocation: result.toolInvocation ?? invocation,
        toolAccess: result.toolAccess ??
            const ToolAccessSnapshot(
              definition: ToolDefinition(
                name: 'fake_tool',
                title: 'fake_tool',
              ),
              executionDecision: ToolPolicyDecision.autoRun,
              executionPolicyLabel: 'auto_run',
              isVisibleToPlanner: true,
            ),
      );
    }
    return result;
  }
}

class _ThrowingToolCallService extends ToolCallService {
  final ToolInvocation invocation;
  final Object error;

  _ThrowingToolCallService({
    required this.invocation,
    required this.error,
  }) : super(
          toolExecutor: ToolExecutor(chatStorage: _NoopChatStorage()),
        );

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    List<ChatEvent> currentTurnEvents = const <ChatEvent>[],
    ToolExecutionStartedCallback? onExecutionStarted,
  }) async {
    if (onExecutionStarted != null) {
      await onExecutionStarted(
        invocation: this.invocation,
        toolAccess: const ToolAccessSnapshot(
          definition: ToolDefinition(
            name: 'create_reminder',
            title: 'create_reminder',
          ),
          executionDecision: ToolPolicyDecision.autoRun,
          executionPolicyLabel: 'auto_run',
          isVisibleToPlanner: true,
        ),
      );
    }
    throw error;
  }
}

class _InMemoryChatTurnRepository extends ChatTurnRepository {
  final Map<int, ChatTurn> turns = {};

  _InMemoryChatTurnRepository() : super(_NoopChatStorage());

  @override
  Future<int> createTurn(ChatTurn turn) async {
    final id = turn.id ?? turns.length + 1;
    turns[id] = turn.copyWith(id: id);
    return id;
  }

  @override
  Future<ChatTurn?> getTurn(int id) async => turns[id];

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async {
    final matching =
        turns.values.where((turn) => turn.groupId == groupId).toList();
    matching.sort((left, right) {
      final leftId = left.id ?? 0;
      final rightId = right.id ?? 0;
      return leftId.compareTo(rightId);
    });
    return matching;
  }

  @override
  Future<void> markAwaitingToolConfirmation(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.awaitingToolConfirmation,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markAwaitingUserInteraction(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.awaitingUserInteraction,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markRunning(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.running,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> incrementIterationAndToolCount(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      iterationCount: turn.iterationCount + 1,
      toolCallCount: turn.toolCallCount + 1,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> incrementToolCallCount(int turnId, {int by = 1}) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      toolCallCount: turn.toolCallCount + by,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markCompleted(
    int turnId, {
    String? stopReason,
    String? finalResponseText,
  }) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.completed,
      stopReason: stopReason,
      finalResponseText: finalResponseText,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markFailed(int turnId, {String? errorMessage}) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.failed,
      errorMessage: errorMessage,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> incrementIteration(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      iterationCount: turn.iterationCount + 1,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateRuntimeState(
    int turnId, {
    ChatTurnProviderStyle? providerStyle,
    String? modelName,
    Map<String, dynamic>? providerStateJson,
  }) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      providerStyle: providerStyle ?? turn.providerStyle,
      modelName: modelName ?? turn.modelName,
      providerStateJson: providerStateJson ?? turn.providerStateJson,
      updatedAt: DateTime.now(),
    );
  }
}

class _InMemoryChatTurnStepRepository extends ChatTurnStepRepository {
  final Map<int, ChatTurnStep> steps = {};

  _InMemoryChatTurnStepRepository() : super(_NoopChatStorage());

  @override
  Future<int> createStep(ChatTurnStep step) async {
    final id = step.id ?? steps.length + 1;
    steps[id] = step.copyWith(id: id);
    return id;
  }

  @override
  Future<List<ChatTurnStep>> listSteps(int turnId) async {
    final matching =
        steps.values.where((step) => step.turnId == turnId).toList();
    matching.sort((left, right) => left.stepIndex.compareTo(right.stepIndex));
    return matching;
  }

  @override
  Future<ChatTurnStep?> getStep(int id) async => steps[id];

  @override
  Future<void> markRunning(int stepId) async {
    final step = steps[stepId]!;
    steps[stepId] = step.copyWith(
      status: ChatTurnStepStatus.running,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markCompleted(
    int stepId, {
    required String resultSummary,
    Map<String, dynamic>? resultJson,
  }) async {
    final step = steps[stepId]!;
    steps[stepId] = step.copyWith(
      status: ChatTurnStepStatus.completed,
      resultSummary: resultSummary,
      resultJson: resultJson ?? step.resultJson,
      updatedAt: DateTime.now(),
      completedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markFailed(
    int stepId, {
    required String errorCode,
    String? resultSummary,
    Map<String, dynamic>? resultJson,
  }) async {
    final step = steps[stepId]!;
    steps[stepId] = step.copyWith(
      status: ChatTurnStepStatus.failed,
      errorCode: errorCode,
      resultSummary: resultSummary ?? step.resultSummary,
      resultJson: resultJson ?? step.resultJson,
      updatedAt: DateTime.now(),
      completedAt: DateTime.now(),
    );
  }
}

class _InMemoryChatEventRepository extends ChatEventRepository {
  final List<ChatEvent> events = [];

  _InMemoryChatEventRepository() : super(_NoopChatStorage());

  @override
  Future<ChatEvent> appendUserMessage({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: content,
    );
  }

  @override
  Future<ChatEvent> appendToolResult({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolResult,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendToolCall({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantToolCall,
      role: MessageRole.assistant,
      content: summary,
      payloadJson: payloadJson ??
          {
            'toolName': toolName,
            'arguments': arguments,
          },
    );
  }

  @override
  Future<ChatEvent> appendToolConfirmation({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantToolConfirmation,
      role: MessageRole.assistant,
      content: summary,
      payloadJson: payloadJson ??
          {
            'toolName': toolName,
            'arguments': arguments,
          },
    );
  }

  @override
  Future<ChatEvent> appendToolExecutionStarted({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolExecutionStarted,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendAssistantQuestionPrompt({
    required int turnId,
    required int groupId,
    required AskUserQuestionRequest request,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantQuestionPrompt,
      role: MessageRole.assistant,
      content: content,
      payloadJson: payloadJson ?? request.toJson(),
    );
  }

  @override
  Future<ChatEvent> appendUserInteractionResult({
    required int turnId,
    required int groupId,
    required AskUserQuestionResponse response,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userInteractionResult,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson ?? response.toJson(),
    );
  }

  @override
  Future<ChatEvent> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolError,
      role: MessageRole.system,
      content: content,
      status: errorCode,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendAssistantTextDelta({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextDelta,
      role: MessageRole.assistant,
      content: content,
    );
  }

  @override
  Future<ChatEvent> appendAssistantReasoningDelta({
    required int turnId,
    required int groupId,
    required String content,
    required String scope,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantReasoningDelta,
      role: MessageRole.assistant,
      content: content,
      payloadJson: {'scope': scope},
    );
  }

  @override
  Future<ChatEvent> appendAssistantPlannerMessage({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantPlannerMessage,
      role: MessageRole.assistant,
      content: content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendAssistantTextFinal({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextFinal,
      role: MessageRole.assistant,
      content: content,
    );
  }

  @override
  Future<ChatEvent> appendFinalAnswer({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.finalAnswer,
      role: MessageRole.assistant,
      content: content,
    );
  }

  @override
  Future<ChatEvent> appendTurnStatus({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.turnStatus,
      role: MessageRole.system,
      content: content,
    );
  }

  @override
  Future<List<ChatEvent>> listEventsByTurn(int turnId) async {
    return events.where((event) => event.turnId == turnId).toList();
  }

  @override
  Future<List<ChatEvent>> listEventsByGroup(int groupId) async {
    return events.where((event) => event.groupId == groupId).toList();
  }

  Future<ChatEvent> _append({
    required int turnId,
    required int groupId,
    required ChatEventType eventType,
    MessageRole? role,
    String? content,
    Map<String, dynamic>? payloadJson,
    String? status,
  }) async {
    final event = ChatEvent(
      id: events.length + 1,
      turnId: turnId,
      groupId: groupId,
      sequence: events.where((item) => item.turnId == turnId).length + 1,
      eventType: eventType,
      role: role,
      content: content,
      payloadJson: payloadJson,
      status: status,
    );
    events.add(event);
    return event;
  }
}

class _FakeDecisionToolCallExecutor implements DecisionToolCallExecutor {
  final List<_DecisionExecutorCall> executeCalls = [];
  final List<DecisionToolExecutionUpdate> updates;

  _FakeDecisionToolCallExecutor({
    this.updates = const [],
  });

  @override
  Stream<DecisionToolExecutionUpdate> executeDecisionToolCalls({
    required ChatTurn turn,
    required ModelTurnDecision decision,
    required ChatConfig config,
    required int consecutiveFailures,
    int? sharedStepId,
  }) async* {
    executeCalls.add(
      _DecisionExecutorCall(
        turn: turn,
        decision: decision,
        consecutiveFailures: consecutiveFailures,
        sharedStepId: sharedStepId,
      ),
    );
    for (final update in updates) {
      yield update;
    }
  }
}

class _DecisionExecutorCall {
  final ChatTurn turn;
  final ModelTurnDecision decision;
  final int consecutiveFailures;
  final int? sharedStepId;

  _DecisionExecutorCall({
    required this.turn,
    required this.decision,
    required this.consecutiveFailures,
    required this.sharedStepId,
  });
}

class _StubSessionContextService extends SessionContextService {
  final List<_PlannerContextCall> calls = [];

  _StubSessionContextService()
      : super(
          chatTurnRepository: _InMemoryChatTurnRepository(),
          chatEventRepository: _InMemoryChatEventRepository(),
          snapshotRepository: SessionContextSnapshotRepository(
            _NoopChatStorage(),
          ),
          contextProjector: SessionContextProjector(),
          tokenBudgetService: SessionTokenBudgetService(),
          summaryService: SessionSummaryService(
            summaryGenerator: (_) async => 'summary',
          ),
          chatService: ChatService(llm: _NoopBaseLLM()),
        );

  @override
  Future<List<ChatMessage>> buildPlannerMessages({
    required int groupId,
    required int currentTurnId,
    required List<ChatEvent> currentTurnTranscript,
    required ChatConfig config,
  }) async {
    calls.add(
      _PlannerContextCall(
        groupId: groupId,
        currentTurnId: currentTurnId,
        currentTurnTranscript: List<ChatEvent>.from(currentTurnTranscript),
      ),
    );
    return [
      ChatMessage(
        text: 'ctx-call-${calls.length}',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }
}

class _PlannerContextCall {
  final int groupId;
  final int currentTurnId;
  final List<ChatEvent> currentTurnTranscript;

  const _PlannerContextCall({
    required this.groupId,
    required this.currentTurnId,
    required this.currentTurnTranscript,
  });
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async =>
      null;

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';
}

class _NoopChatStorage implements ChatStorage {
  @override
  Future<int> insertOrReplaceArtifactRecord(ArtifactRecord record) async => 1;

  @override
  Future<ArtifactRecord?> getArtifactRecord({
    required int groupId,
    required String artifactId,
  }) async =>
      null;

  @override
  Future<ArtifactRecord?> getArtifactRecordByPath({
    required int groupId,
    required String sourcePath,
  }) async =>
      null;

  @override
  Future<List<ArtifactRecord>> listArtifactRecordsForGroup(int groupId) async =>
      const [];

  @override
  Future<void> updateArtifactRecord(ArtifactRecord record) async {}

  @override
  Future<void> deleteGroup(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteGroupMessages(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteMessage(int id) => throw UnimplementedError();

  @override
  Future<List<ChatEvent>> getEventsByGroup(int groupId) async => const [];

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async => const [];

  @override
  Future<int> getNextEventSequence(int turnId) async => 1;

  @override
  Future<List<ChatGroup>> getAllGroups() => throw UnimplementedError();

  @override
  Future<int> getGroupMessageCount(int groupId) => throw UnimplementedError();

  @override
  Future<ChatGroup?> getLatestGroup() => throw UnimplementedError();

  @override
  Future<ChatGroup?> getGroupById(int id) async => ChatGroup(
        id: id,
        title: 'stub',
        lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
      );

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) async =>
      null;

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async => const [];

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) =>
      throw UnimplementedError();

  @override
  Future<ChatTurn?> getTurn(int id) async => null;

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async => const [];

  @override
  Future<ChatTurnStep?> getTurnStep(int id) async => null;

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) async => const [];

  @override
  Future<int> insertEvent(ChatEvent event) => throw UnimplementedError();

  @override
  Future<int> insertGroup(ChatGroup group) => throw UnimplementedError();

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) =>
      throw UnimplementedError();

  @override
  Future<int> insertSessionContextSnapshot(SessionContextSnapshot snapshot) =>
      throw UnimplementedError();

  @override
  Future<int> insertSessionRuntimeMarker(SessionRuntimeMarker marker) =>
      throw UnimplementedError();

  @override
  Future<int> insertTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<int> insertTurnStep(ChatTurnStep step) => throw UnimplementedError();

  @override
  Future<bool> testDatabaseConnection() async => true;

  @override
  Future<SessionRuntimeMarker?> getLatestSessionRuntimeMarkerByGroup(
    int groupId,
  ) async =>
      null;

  @override
  Future<void> updateGroupLastMessageTime(int groupId) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupTitle(int groupId, String title,
          {bool isSummarized = true}) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessage(int id, String newText) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessageReasoning(int id, String? reasoningContent) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessageStatus(int id, MessageStatus status) =>
      throw UnimplementedError();

  @override
  Future<void> updateSessionContextSnapshot(
    SessionContextSnapshot snapshot,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> updateSessionRuntimeMarker(SessionRuntimeMarker marker) =>
      throw UnimplementedError();

  @override
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required contentType,
    String? payloadJson,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<void> updateTurnStep(ChatTurnStep step) => throw UnimplementedError();
}
