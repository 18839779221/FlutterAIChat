import 'dart:async';
import 'dart:collection';

import 'package:ai_chat/models/agent/agent_action.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/tool/tool_access_snapshot.dart';
import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/agent/stop_verification_result.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_call.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TurnHarness', () {
    test('runs tool call, records tool result, then streams final answer',
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
        chatService: _FakeChatService(
          chunks: const ['最终', '回答'],
        ),
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
                description: '搜索历史消息',
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
            additionalContextMessages: [
              ChatMessage(
                text:
                    '以下是工具 `search_chat_history` 的执行结果，请结合这些信息回答用户。\n状态：success\n查询词：数据库\n命中历史消息：\n- [assistant] 数据库版本是 7',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.finalAnswer,
        ]),
      );
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
        chatService: _FakeChatService(chunks: const []),
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
                description: '创建系统提醒',
              ),
              executionDecision: ToolPolicyDecision.requireConfirmation,
              executionPolicyLabel: 'require_confirmation',
              isVisibleToPlanner: true,
            ),
            toolResult: null,
            additionalContextMessages: [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        chatService: _FakeChatService(chunks: const []),
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
            additionalContextMessages: [],
          ),
        ),
        limits:
            const AgentLoopLimits(maxIterations: 4, maxConsecutiveFailures: 1),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .toList();

      expect(emitted.map((event) => event.eventType),
          contains(ChatEventType.toolError));
      expect((await turnRepository.getTurn(3))!.status, ChatTurnStatus.failed);
    });

    test('continues repeated retrieval steps based on loop state rather than planner patching',
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
        chatService: _FakeChatService(
          chunks: const ['最终', '结论'],
        ),
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
            additionalContextMessages: [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 5),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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

    test('does not execute an identical tool call twice within the same turn',
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
          ]),
          toolPolicyService: await _createToolPolicyService(),
          availableTools: const [
            ToolDefinition(
              name: 'search_chat_history',
              title: '搜索聊天记录',
              description: '搜索聊天记录',
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
        chatService: _FakeChatService(chunks: const []),
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
            additionalContextMessages: [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .toList();

      final toolResults = emitted
          .where((event) => event.eventType == ChatEventType.toolResult)
          .toList(growable: false);
      expect(toolResults, hasLength(1));
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
        'resumes awaiting confirmation turn, executes tool, then streams final answer',
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
        chatService: _FakeChatService(
          chunks: const ['提醒', '已创建'],
        ),
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
            additionalContextMessages: [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
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
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
            trustTool: true,
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.finalAnswer,
        ]),
      );
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
        chatService: _FakeChatService(
          chunks: const ['提醒已记录'],
        ),
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
            additionalContextMessages: [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 2),
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
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        chatService: _FakeChatService(
          chunks: const ['提醒已记录'],
        ),
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
            additionalContextMessages: [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 2),
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
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        chatService: _FakeChatService(chunks: const ['unused']),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
          definitionsByName: const {
            'ask_user_question': ToolDefinition(
              name: 'ask_user_question',
              title: '向用户提问',
              description: '向用户发起结构化问题',
              runtimeKind: ToolRuntimeKind.userInteraction,
            ),
          },
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        chatService: _FakeChatService(
          chunks: const ['建议先用 SQLite。'],
        ),
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(maxIterations: 4),
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
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .toList();

      expect(toolCallService.executeInvocationCount, 0);
      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userInteractionResult,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.finalAnswer,
        ]),
      );
      final step = (await stepRepository.getStep(9))!;
      expect(step.status, ChatTurnStepStatus.completed);
      expect(step.providerCallId, 'call_ask_1');
      expect(
        step.resultJson?['answersByQuestionId'],
        containsPair('storage_layer', 'SQLite'),
      );
      expect(
        (await turnRepository.getTurn(turnId))!.status,
        ChatTurnStatus.completed,
      );
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
        chatService: _FakeChatService(
          chunks: const ['未完成'],
        ),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxIterations: 1),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.turnStatus,
        ]),
      );
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
        chatService: _FakeChatService(chunks: const []),
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
            additionalContextMessages: [
              ChatMessage(
                text: '数据库版本是 7',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
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
            additionalContextMessages: [],
          ),
        ]),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        'records planner request failure as turn status before streaming final answer',
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
        chatService: _FakeChatService(
          chunks: const ['最终回答'],
        ),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.turnStatus,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.finalAnswer,
        ]),
      );
      expect(
        emitted
            .where((event) => event.eventType == ChatEventType.turnStatus)
            .map((event) => event.content),
        contains('planner_request_failed'),
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
        chatService: _FakeChatService(
          chunks: const ['最终回答'],
        ),
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
            additionalContextMessages: [
              ChatMessage(
                text:
                    '以下是工具 `web_search` 的执行结果，请结合这些信息回答用户。\n状态：success\n查询词：Claude latest news\n联网搜索结果：\n- [example.com] Claude 3.7 Sonnet announced\n  摘要：Anthropic introduced a hybrid reasoning model.\n  链接：https://example.com/claude-3-7',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        'executes multiple provider-native tool calls and sends ledger summary',
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
              toolName: 'save_note',
              arguments: {
                'title': '数据库版本确认',
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
      final chatService = _FakeChatService(
        chunks: const ['最终回答'],
      );

      final harness = TurnHarness(
        plannerService: plannerService,
        turnRepository: turnRepository,
        turnStepRepository: stepRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        turnVerifier: _AlwaysStopVerifier(),
        chatService: chatService,
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
            additionalContextMessages: [
              ChatMessage(
                text:
                    '以下是工具 `search_chat_history` 的执行结果，请结合这些信息回答用户。\n命中历史消息：数据库版本是 7，发版时间是 2026-04-12 10:00',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
          ),
          const ToolPreparationResult(
            toolInvocation: ToolInvocation(
              toolName: 'save_note',
              arguments: {
                'title': '数据库版本确认',
                'content': '数据库版本 7，发版时间 2026-04-12 10:00',
              },
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：保存笔记',
              requiresConfirmation: false,
            ),
            toolResult: ToolResult(
              toolName: 'save_note',
              status: ToolExecutionStatus.success,
              summary: '已保存笔记《数据库版本确认》',
              data: {
                'title': '数据库版本确认',
                'folder': '默认',
              },
            ),
            additionalContextMessages: [],
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
            additionalContextMessages: [],
          ),
        ]),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await harness
          .runTurn(
            turn: turn,
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
          )
          .toList();

      expect(plannerService.nativeDecisionCalls, 2);
      expect(plannerService.legacyActionCalls, 0);
      final toolResults = emitted
          .where((event) => event.eventType == ChatEventType.toolResult)
          .toList(growable: false);
      expect(toolResults, hasLength(3));
      expect(toolResults.map((event) => event.content), [
        '已执行：搜索历史记录',
        '已保存笔记《数据库版本确认》',
        '已创建提醒：今晚 8 点同步给测试同学',
      ]);
      expect(
        toolResults.map((event) => event.content).join('\n'),
        isNot(contains('命中历史消息')),
      );

      final finalAnswerMessages =
          chatService.capturedFinalAnswerMessages.single;
      final finalAnswerPrompt =
          finalAnswerMessages.map((message) => message.text).join('\n');
      expect(finalAnswerPrompt, contains('本轮工具执行总结：'));
      expect(finalAnswerPrompt, contains('1. search_chat_history'));
      expect(finalAnswerPrompt, contains('2. save_note'));
      expect(finalAnswerPrompt, contains('3. create_reminder'));
      expect(finalAnswerPrompt, contains('"matchCount":1'));
      expect(finalAnswerPrompt, contains('数据库版本确认'));
      expect(finalAnswerPrompt, contains('数据库版本 7，发版时间 2026-04-12 10:00'));
      expect(finalAnswerPrompt, isNot(contains('命中历史消息')));
      expect(await stepRepository.listSteps(turnId), hasLength(3));

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
  }) async {
    capturedTranscripts.add(List<ChatEvent>.from(transcript));
    return _decisionFromAction(actions.removeFirst());
  }

  @override
  Future<AgentAction> planNextAction({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    throw StateError('legacy planner path should not be used');
  }
}

class _NativeDecisionPlannerService extends AgentPlannerService {
  final Queue<ModelTurnDecision> decisions;
  int nativeDecisionCalls = 0;
  int legacyActionCalls = 0;

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
  }) async {
    nativeDecisionCalls += 1;
    final decision = decisions.removeFirst();
    return decision.copyWith(
      providerStyle:
          decision.providerStyle ?? ChatTurnProviderStyle.openaiResponses,
      modelName: decision.modelName ?? 'gpt-5.4',
    );
  }

  @override
  Future<AgentAction> planNextAction({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    legacyActionCalls += 1;
    throw StateError('legacy planner path should not be used');
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
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    if (decisions.isEmpty) {
      throw StateError('No more queued native decisions');
    }
    return decisions.removeFirst();
  }

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      '{"action":"respond","response":"fallback"}';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Stream<String> chatStream(
    List<ChatMessage> messages,
    ChatConfig config,
  ) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
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

class _FakeChatService extends ChatService {
  final List<String> chunks;
  final List<List<ChatMessage>> capturedFinalAnswerMessages = [];

  _FakeChatService({required this.chunks}) : super(llm: _NoopBaseLLM());

  @override
  Stream<String> streamFinalAnswer({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async* {
    capturedFinalAnswerMessages.add(List<ChatMessage>.from(messages));
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

class _FakeToolCallService extends ToolCallService {
  final ToolPreparationResult executeResult;
  final Map<String, ToolDefinition> definitionsByName;
  int executeInvocationCount = 0;

  _FakeToolCallService({
    required this.executeResult,
    this.definitionsByName = const {},
  })
      : super(
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
  }) async {
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
  }) async {
    return executeResults.removeFirst();
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
  Future<int> appendUserMessage({
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
  Future<int> appendToolResult({
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
  Future<int> appendToolCall({
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
  Future<int> appendToolConfirmation({
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
  Future<int> appendToolExecutionStarted({
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
  Future<int> appendAssistantQuestionPrompt({
    required int turnId,
    required int groupId,
    required AskUserQuestionRequest request,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantQuestionPrompt,
      role: MessageRole.assistant,
      content: content,
      payloadJson: request.toJson(),
    );
  }

  @override
  Future<int> appendUserInteractionResult({
    required int turnId,
    required int groupId,
    required AskUserQuestionResponse response,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userInteractionResult,
      role: MessageRole.system,
      content: content,
      payloadJson: response.toJson(),
    );
  }

  @override
  Future<int> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolError,
      role: MessageRole.system,
      content: content,
      status: errorCode,
    );
  }

  @override
  Future<int> appendAssistantTextDelta({
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
  Future<int> appendAssistantTextFinal({
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
  Future<int> appendFinalAnswer({
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
  Future<int> appendTurnStatus({
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

  Future<int> appendEvent(ChatEvent event) async {
    events.add(event);
    return events.length;
  }

  Future<int> _append({
    required int turnId,
    required int groupId,
    required ChatEventType eventType,
    MessageRole? role,
    String? content,
    Map<String, dynamic>? payloadJson,
    String? status,
  }) async {
    final event = ChatEvent(
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
    return events.length;
  }
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async =>
      '{"action":"respond","response":"noop"}';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async =>
      null;

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _NoopChatStorage implements ChatStorage {
  @override
  Future<void> deleteGroup(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteGroupMessages(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteMessage(int id) => throw UnimplementedError();

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async => const [];

  @override
  Future<List<ChatGroup>> getAllGroups() => throw UnimplementedError();

  @override
  Future<int> getGroupMessageCount(int groupId) => throw UnimplementedError();

  @override
  Future<ChatGroup?> getLatestGroup() => throw UnimplementedError();

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
  Future<int> insertTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<int> insertTurnStep(ChatTurnStep step) => throw UnimplementedError();

  @override
  Future<bool> testDatabaseConnection() async => true;

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
