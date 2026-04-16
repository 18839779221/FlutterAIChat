import 'package:ai_chat/models/agent/agent_action.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_argument_property.dart';
import 'package:ai_chat/models/tool/tool_argument_schema.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AgentPlannerService', () {
    test('parses respond action from valid json', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse: '{"action":"respond","response":"这是最终回答"}',
        ),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, '这是最终回答');
      expect(result.toolCall, isNull);
      expect(result.diagnosticCode, 'planner_action_respond');
    });

    test('parses callTool action from valid json', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{"action":"call_tool","toolName":"search_chat_history","arguments":{"query":"数据库","maxResults":3}}',
        ),
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
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.callTool);
      expect(result.toolCall, isNotNull);
      expect(result.toolCall!.toolName, 'search_chat_history');
      expect(result.toolCall!.arguments, containsPair('query', '数据库'));
      expect(result.diagnosticCode, 'planner_action_call_tool');
    });

    test(
        'parses first json object when planner emits duplicated responses payload',
        () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{"action":"call_tool","toolName":"web_search","arguments":{"query":"Claude 最新进展","top_k":5}}'
              '{"action":"call_tool","toolName":"web_search","arguments":{"query":"Claude 最新进展","top_k":5}}',
        ),
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '当用户需要最新外部资料时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
        ],
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.callTool);
      expect(result.toolCall, isNotNull);
      expect(result.toolCall!.toolName, 'web_search');
      expect(result.toolCall!.arguments, containsPair('query', 'Claude 最新进展'));
      expect(result.diagnosticCode, 'planner_action_call_tool');
    });

    test('trims planner action and tool name before matching runtime tools',
        () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{\n  "action":" call_tool\\n",\n  "toolName":" web_search\\t",\n  "arguments":{"query":"OpenAI 最新新闻"}\n}',
        ),
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '当用户需要最新外部资料时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
        ],
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.callTool);
      expect(result.toolCall, isNotNull);
      expect(result.toolCall!.toolName, 'web_search');
      expect(result.toolCall!.arguments, containsPair('query', 'OpenAI 最新新闻'));
      expect(result.diagnosticCode, 'planner_action_call_tool');
    });

    test('falls back to respond when planner output is malformed', () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(plannerResponse: 'not-json'),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, contains('抱歉'));
      expect(result.diagnosticCode, 'planner_parse_failed');
    });

    test(
        'planner prompt exposes runtime-available tool names without heuristic hiding',
        () async {
      final llm = _FakePlannerLLM(
        plannerResponse: '{"action":"respond","response":"ok"}',
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '当用户需要最新外部资料时使用。',
            whenToUse: ['用户询问最新消息'],
            whenNotToUse: ['用户已经提供 URL'],
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
          ToolDefinition(
            name: 'fetch_webpage',
            title: '读取网页',
            description: '读取网页',
            descriptionForModel: '当用户已经提供 URL 时使用。',
            whenToUse: ['用户消息中有 URL'],
            whenNotToUse: ['只是需要联网搜索'],
            argumentSchema: ToolArgumentSchema(
              properties: {
                'url': ToolArgumentProperty.string(description: '链接'),
              },
              required: ['url'],
            ),
          ),
          ToolDefinition(
            name: 'share_result',
            title: '分享结果',
            description: '分享文本',
            descriptionForModel: '用户明确要求分享时使用。',
            category: ToolCategory.outputAction,
            whenToUse: ['用户明确说分享'],
            whenNotToUse: ['用户只是查资料'],
            argumentSchema: ToolArgumentSchema(
              properties: {
                'text': ToolArgumentProperty.string(description: '分享正文'),
              },
              required: ['text'],
            ),
          ),
        ],
      );

      await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastMessages.first.text,
        contains('你是一个对话回合规划器'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('web_search'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('当用户需要最新外部资料时使用。'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('什么时候使用'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('如果已有足够信息则直接回答用户'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('fetch_webpage'),
      );
      expect(
        llm.lastMessages.first.text,
        contains('share_result'),
      );
    });

    test('planNextDecision includes tool execution policy in planner prompt',
        () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final policyService = ToolPolicyService(
        repository: AppSettingsRepository(
          preferences,
          localDefaultsLoader: () async => null,
        ),
      );
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: policyService,
        availableTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '当用户需要最新外部资料时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
          ToolDefinition(
            name: 'create_reminder',
            title: '创建提醒',
            description: '创建系统提醒',
            descriptionForModel: '当用户明确要求提醒时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
              },
              required: ['title'],
            ),
            requiresConfirmation: true,
            riskLevel: 'medium',
          ),
        ],
      );

      await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastMessages.first.text, contains('执行策略：auto_run'));
      expect(
        llm.lastMessages.first.text,
        contains('执行策略：require_confirmation'),
      );
    });

    test('planNextDecision annotates structured planner tool options with policy',
        () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final policyService = ToolPolicyService(
        repository: AppSettingsRepository(
          preferences,
          localDefaultsLoader: () async => null,
        ),
      );
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: policyService,
        availableTools: const [
          ToolDefinition(
            name: 'create_reminder',
            title: '创建提醒',
            description: '创建系统提醒',
            descriptionForModel: '当用户明确要求提醒时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
              },
              required: ['title'],
            ),
            requiresConfirmation: true,
            riskLevel: 'medium',
          ),
        ],
      );

      await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolOptions, isNotNull);
      expect(
        llm.lastToolOptions!.single.description,
        contains('Execution policy: require_confirmation'),
      );
    });

    test(
        'planNextDecision requires tool policy service when resolving visible tools',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        availableTools: const [
          ToolDefinition(
            name: 'create_reminder',
            title: '创建提醒',
            description: '创建系统提醒',
            descriptionForModel: '当用户明确要求提醒时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
              },
              required: ['title'],
            ),
            requiresConfirmation: true,
            riskLevel: 'medium',
          ),
        ],
      );

      await expectLater(
        () => service.planNextDecision(
          turn: _turn(),
          transcript: [_userEvent()],
          steps: const [],
          config: ChatConfig(useReasoning: false, systemPrompt: ''),
          limits: const AgentLoopLimits(),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('toolPolicyService is required'),
          ),
        ),
      );
    });

    test('falls back to respond when planner emits an unknown tool name',
        () async {
      final service = AgentPlannerService(
        llm: _FakePlannerLLM(
          plannerResponse:
              '{"action":"call_tool","toolName":"search_news","arguments":{"query":"OpenAI 最新新闻"}}',
        ),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, contains('暂时无法规划'));
      expect(result.toolCall, isNull);
      expect(result.diagnosticCode, 'planner_unsupported_tool');
    });

    test(
        'falls back to respond with request failure diagnostic when planner throws',
        () async {
      final service = AgentPlannerService(
        llm: _ThrowingPlannerLLM(),
      );

      final result = await service.planNextAction(
        turn: _turn(),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result.type, AgentActionType.respond);
      expect(result.response, contains('暂时无法规划'));
      expect(result.diagnosticCode, 'planner_request_failed');
    });

    test('planner messages include structured tool state summary', () async {
      final llm = _FakePlannerLLM(
        plannerResponse: '{"action":"respond","response":"ok"}',
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
        ],
      );

      await service.planNextAction(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我总结网页',
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：web_search',
            payloadJson: {
              'toolName': 'web_search',
              'arguments': {'query': 'Anthropic latest'},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已读取网页正文',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolError,
            role: MessageRole.system,
            content: '读取失败',
            status: 'network_error',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastMessages[1].text, contains('已尝试工具：web_search'));
      expect(llm.lastMessages[1].text, contains('最近一次工具结果：已读取网页正文'));
      expect(llm.lastMessages[1].text, contains('最近一次工具失败：network_error'));
    });

    test('planNextDecision sends ledger summary and filters unsupported tools',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              providerCallId: 'call_1',
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              sequence: 1,
            ),
            ModelToolCall(
              providerCallId: 'call_2',
              toolName: 'unsupported_tool',
              arguments: {'foo': 'bar'},
              sequence: 2,
            ),
          ],
          assistantMessage: null,
          providerState: {'response_id': 'resp_123'},
          isTerminal: false,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
          ToolDefinition(
            name: 'save_note',
            title: '保存笔记',
            description: '保存笔记',
            descriptionForModel: '当用户要求沉淀结论时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
                'content': ToolArgumentProperty.string(description: '正文'),
              },
              required: ['title', 'content'],
            ),
          ),
        ],
      );

      final decision = await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我确认数据库版本',
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我确认数据库版本',
          ),
        ],
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 1,
            stepIndex: 1,
            toolName: 'search_chat_history',
            toolArgsJson: const {'query': '数据库版本'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已执行：搜索历史记录',
            resultJson: const {
              'query': '数据库版本',
              'matchCount': 1,
              'matches': [
                {
                  'text': '数据库版本是 7',
                  'role': 'assistant',
                },
              ],
            },
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.diagnosticCode, 'planner_duplicate_tool_call');
      expect(decision.isTerminal, isTrue);
      expect(llm.lastMessages[1].text, contains('已完成步骤：'));
      expect(llm.lastMessages[1].text, contains('search_chat_history'));
      expect(llm.lastMessages[1].text, contains('"matchCount":1'));
    });

    test('planNextDecision forwards turn runtime provider state to llm',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {'response_id': 'resp_234'},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
          ToolDefinition(
            name: 'save_note',
            title: '保存笔记',
            description: '保存笔记',
            descriptionForModel: '当用户要求沉淀结论时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
                'content': ToolArgumentProperty.string(description: '正文'),
              },
              required: ['title', 'content'],
            ),
          ),
        ],
      );

      await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续上一轮 responses tool loop',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          providerStateJson: const {'response_id': 'resp_prev'},
        ),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastProviderStyle, ChatTurnProviderStyle.openaiResponses);
      expect(llm.lastProviderState, containsPair('response_id', 'resp_prev'));
    });

    test(
        'planNextDecision builds responses continuation items from current response steps',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {'response_id': 'resp_next'},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
        ],
      );

      await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续执行 responses tool loop',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          providerStateJson: const {'response_id': 'resp_prev'},
        ),
        transcript: [_userEvent()],
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 1,
            stepIndex: 1,
            providerResponseId: 'resp_prev',
            providerCallId: 'fc_1',
            toolName: 'search_chat_history',
            toolArgsJson: const {'query': '数据库版本'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已确认数据库版本 7',
            resultJson: const {'databaseVersion': '7'},
          ),
          ChatTurnStep(
            id: 2,
            turnId: 1,
            stepIndex: 2,
            providerResponseId: 'resp_old',
            providerCallId: 'fc_old',
            toolName: 'save_note',
            toolArgsJson: const {'title': '旧笔记'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '旧结果',
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastProviderContinuationItems, hasLength(1));
      expect(
        llm.lastProviderContinuationItems.single,
        containsPair('type', 'function_call_output'),
      );
      expect(
        llm.lastProviderContinuationItems.single,
        containsPair('call_id', 'fc_1'),
      );
      expect(
        llm.lastProviderContinuationItems.single['output'] as String,
        contains('"status":"success"'),
      );
      expect(
        llm.lastProviderContinuationItems.single['output'] as String,
        contains('"databaseVersion":"7"'),
      );
    });

    test(
        'planNextDecision returns terminal planner failure when native planner returns null',
        () async {
      final llm = _NativeNullThenLegacyPlannerLLM(
        plannerResponse:
            '{"action":"call_tool","toolName":"search_chat_history","arguments":{"query":"数据库版本"}}',
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
        ],
      );

      final decision = await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, contains('暂时无法规划'));
      expect(decision.diagnosticCode, 'planner_request_failed');
      expect(decision.isTerminal, isTrue);
      expect(llm.nativeAttempts, 1);
      expect(llm.legacyAttempts, 0);
    });

    test(
        'planNextDecision returns terminal planner failure when native planner throws',
        () async {
      final llm = _NativeThenLegacyPlannerLLM(
        plannerResponse:
            '{"action":"call_tool","toolName":"search_chat_history","arguments":{"query":"数据库版本"}}',
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
        ],
      );

      final decision = await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, contains('暂时无法规划'));
      expect(decision.diagnosticCode, 'planner_request_failed');
      expect(decision.isTerminal, isTrue);
      expect(llm.nativeAttempts, 1);
      expect(llm.legacyAttempts, 0);
    });

    test('planNextDecision does not fall back to a static tool allowlist',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          providerState: {},
          isTerminal: false,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [],
      );

      final decision = await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.diagnosticCode, 'planner_unsupported_tool');
      expect(decision.isTerminal, isTrue);
    });

    test('planNextDecision only accepts tools from the visible tool set',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'save_note',
              arguments: {'title': '数据库版本确认', 'content': '数据库版本是 7'},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          providerState: {},
          isTerminal: false,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
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
              },
              required: ['query'],
            ),
          ),
        ],
      );

      final decision = await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.diagnosticCode, 'planner_unsupported_tool');
      expect(decision.isTerminal, isTrue);
    });

    test('planNextDecision filters duplicate tool calls already completed in the same turn',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': 'agent loop', 'maxResults': 5},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          providerState: {},
          isTerminal: false,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
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
      );

      final decision = await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续查 agent loop',
        ),
        transcript: [_userEvent()],
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 1,
            stepIndex: 1,
            toolName: 'search_chat_history',
            toolArgsJson: const {'maxResults': 5, 'query': 'agent loop'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已执行：搜索历史记录',
            resultJson: const {
              'query': 'agent loop',
              'matchCount': 1,
            },
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.diagnosticCode, 'planner_duplicate_tool_call');
      expect(decision.isTerminal, isTrue);
    });

    test('planNextDecision passes visible tool schemas into native planner',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '当用户需要最新外部资料时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
        ],
      );

      await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查一下最新资料',
        ),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolOptions, isNotNull);
      expect(llm.lastToolOptions!.single.name, 'web_search');
      expect(llm.lastToolOptions!.single.inputSchema['required'], ['query']);
    });

    test('planNextDecision parses native planner tool choice directly',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'fetch_webpage',
              arguments: {'url': 'https://example.com'},
              sequence: 1,
            ),
          ],
          assistantMessage: null,
          providerState: {},
          isTerminal: false,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'fetch_webpage',
            title: '读取网页',
            description: '读取网页',
            descriptionForModel: '当用户已经提供 URL 时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'url': ToolArgumentProperty.string(description: '网页链接'),
              },
              required: ['url'],
            ),
          ),
        ],
      );

      final result = await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我读这个 https://example.com',
        ),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result, isNotNull);
      expect(result!.toolCalls, hasLength(1));
      expect(result.toolCalls.single.toolName, 'fetch_webpage');
      expect(result.toolCalls.single.arguments,
          containsPair('url', 'https://example.com'));
    });

    test(
        'planNextAction skips structured planner and uses legacy output directly',
        () async {
      final llm = _StructuredThenLegacyPlannerLLM(
        plannerResponse:
            '{"action":"call_tool","toolName":"web_search","arguments":{"query":"Claude 最新进展"}}',
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'web_search',
            title: '联网搜索',
            description: '搜索外部网页',
            descriptionForModel: '当用户需要最新外部资料时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'query': ToolArgumentProperty.string(description: '搜索词'),
              },
              required: ['query'],
            ),
          ),
        ],
      );

      final result = await service.planNextAction(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查 Claude 最新进展',
        ),
        transcript: [_userEvent()],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.structuredAttempts, 0);
      expect(llm.legacyAttempts, 1);
      expect(result.type, AgentActionType.callTool);
      expect(result.toolCall?.toolName, 'web_search');
    });
  });
}

ChatTurn _turn() => ChatTurn(
      id: 1,
      groupId: 1,
      status: ChatTurnStatus.running,
      userInput: '帮我回忆刚才聊到的数据库版本',
    );

ChatEvent _userEvent() => ChatEvent(
      turnId: 1,
      groupId: 1,
      sequence: 1,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: '帮我回忆刚才聊到的数据库版本',
    );

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

class _FakePlannerLLM implements BaseLLM {
  final String plannerResponse;
  List<ChatMessage> lastMessages = const [];

  _FakePlannerLLM({required this.plannerResponse});

  @override
  Map<String, dynamic> get config => const {};
  @override
  String getModelName(ChatConfig config) => 'fake-planner';

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    lastMessages = List<ChatMessage>.from(messages);
    return plannerResponse;
  }

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
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _ThrowingPlannerLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'throwing-planner';

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    throw Exception('planner unavailable');
  }

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
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _StructuredThenLegacyPlannerLLM implements BaseLLM {
  _StructuredThenLegacyPlannerLLM({required this.plannerResponse});

  final String plannerResponse;
  int structuredAttempts = 0;
  int legacyAttempts = 0;

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'structured-then-legacy';

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async {
    structuredAttempts++;
    throw const FormatException('unexpected end of input');
  }

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
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    legacyAttempts++;
    return plannerResponse;
  }

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _NativeDecisionLLM implements BaseLLM {
  final ModelTurnDecision decision;
  List<ChatMessage> lastMessages = const [];
  List<PlannerToolOption>? lastToolOptions;
  ChatTurnProviderStyle? lastProviderStyle;
  Map<String, dynamic>? lastProviderState;
  List<Map<String, dynamic>> lastProviderContinuationItems = const [];

  _NativeDecisionLLM({required this.decision});

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'native-decision';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    lastMessages = List<ChatMessage>.from(messages);
    lastToolOptions = List<PlannerToolOption>.from(availableTools);
    lastProviderStyle = providerStyle;
    lastProviderState =
        providerState == null ? null : Map<String, dynamic>.from(providerState);
    lastProviderContinuationItems = providerContinuationItems
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    return decision;
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
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _NativeNullThenLegacyPlannerLLM implements BaseLLM {
  final String plannerResponse;
  int nativeAttempts = 0;
  int legacyAttempts = 0;

  _NativeNullThenLegacyPlannerLLM({required this.plannerResponse});

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'native-null-then-legacy';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    nativeAttempts += 1;
    return null;
  }

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    legacyAttempts += 1;
    return plannerResponse;
  }

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _NativeThenLegacyPlannerLLM implements BaseLLM {
  final String plannerResponse;
  int nativeAttempts = 0;
  int legacyAttempts = 0;

  _NativeThenLegacyPlannerLLM({required this.plannerResponse});

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'native-then-legacy';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    nativeAttempts += 1;
    throw Exception('native planner unavailable');
  }

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    legacyAttempts += 1;
    return plannerResponse;
  }

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async =>
      null;

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}
