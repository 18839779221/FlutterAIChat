import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat_message.dart';
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
    test('planNextDecision uses a minimal planner prompt instead of rendering tool policies',
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

      expect(llm.lastMessages.first.text, contains('优先使用原生工具调用来推进任务'));
      expect(llm.lastMessages.first.text, isNot(contains('执行策略')));
      expect(llm.lastMessages.first.text, isNot(contains('create_reminder')));
    });

    test('planNextDecision keeps execution policy separate from tool description',
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
      expect(llm.lastToolOptions!.single.description, '当用户明确要求提醒时使用。');
      expect(llm.lastToolOptions!.single.executionPolicy, 'require_confirmation');
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

    test('planNextDecision returns unsupported-tool failure for invisible tools',
        () async {
      final service = AgentPlannerService(
        llm: _NativeDecisionLLM(
          decision: const ModelTurnDecision(
            toolCalls: [
              ModelToolCall(
                toolName: 'search_news',
                arguments: {'query': 'OpenAI 最新新闻'},
                sequence: 0,
              ),
            ],
            assistantMessage: null,
            providerState: {},
            isTerminal: false,
          ),
        ),
      );

      final result = await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result, isNotNull);
      expect(result!.toolCalls, isEmpty);
      expect(result.assistantMessage, contains('暂时无法规划'));
      expect(result.diagnosticCode, 'planner_unsupported_tool');
    });

    test(
        'falls back to respond with request failure diagnostic when planner throws',
        () async {
      final service = AgentPlannerService(llm: _ThrowingNativePlannerLLM());

      final result = await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result, isNotNull);
      expect(result!.assistantMessage, contains('暂时无法规划'));
      expect(result.diagnosticCode, 'planner_request_failed');
    });

    test('planner messages keep minimal instructions separate from turn summary',
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
        steps: const [],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastMessages.first.text, contains('你是一个对话回合规划器'));
      expect(llm.lastMessages.first.text, isNot(contains('搜索聊天记录')));
      expect(llm.lastMessages[1].text, contains('用户目标：帮我总结网页'));
      expect(llm.lastMessages[1].text, contains('当前轮次：0'));
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
      final llm = _NativeNullPlannerLLM();
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
    });

    test(
        'planNextDecision returns terminal planner failure when native planner throws',
        () async {
      final llm = _ThrowingNativePlannerLLM();
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

class _NativeNullPlannerLLM implements BaseLLM {
  int nativeAttempts = 0;

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'native-null';

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

class _ThrowingNativePlannerLLM implements BaseLLM {
  int nativeAttempts = 0;

  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'throwing-native';

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
