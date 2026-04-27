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
    test(
        'planNextDecision uses a minimal planner prompt instead of rendering tool policies',
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
            descriptionForModel: '当用户明确要求提醒时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
              },
              required: ['title'],
            ),
            requiresConfirmation: true,
          ),
        ],
      );

      await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastConfig?.systemPrompt, contains('next best action'));
      expect(llm.lastConfig?.systemPrompt, contains('Answer directly'));
      expect(llm.lastConfig?.systemPrompt, isNot(contains('create_reminder')));
    });

    test(
        'planNextDecision keeps execution policy separate from tool description',
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
            descriptionForModel: '当用户明确要求提醒时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
              },
              required: ['title'],
            ),
            requiresConfirmation: true,
          ),
        ],
      );

      await service.planNextDecision(
        turn: _turn(),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolOptions, isNotNull);
      expect(llm.lastToolOptions!.single.description, '当用户明确要求提醒时使用。');
      expect(
          llm.lastToolOptions!.single.executionPolicy, 'require_confirmation');
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
            descriptionForModel: '当用户明确要求提醒时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'title': ToolArgumentProperty.string(description: '标题'),
              },
              required: ['title'],
            ),
            requiresConfirmation: true,
          ),
        ],
      );

      await expectLater(
        () => service.planNextDecision(
          turn: _turn(),
          transcript: [_userEvent()],
          steps: const [],
          config: ChatConfig(systemPrompt: ''),
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

    test(
        'planNextDecision returns unsupported-tool failure for invisible tools',
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
        config: ChatConfig(systemPrompt: ''),
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(result, isNotNull);
      expect(result!.assistantMessage, contains('当前模型请求失败'));
      expect(result.assistantMessage, contains('native planner unavailable'));
      expect(result.diagnosticCode, 'planner_request_failed');
    });

    test(
        'planner messages keep minimal instructions separate from turn summary',
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastConfig?.systemPrompt, contains('next best action'));
      expect(llm.lastConfig?.systemPrompt,
          isNot(contains('Do not repeat the same tool call')));
      expect(
          llm.lastMessages.map((message) => message.text), contains('已读取网页正文'));
      expect(llm.lastMessages.map((message) => message.text), contains('读取失败'));
    });

    test('planNextDecision projects ask-user transcript into chat-safe roles',
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
            name: 'ask_user_question',
            title: '向用户提问',
            descriptionForModel: '当必须补充关键信息时使用。',
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
      );

      await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我确认应该用什么本地存储',
          providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我确认应该用什么本地存储',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantPlannerMessage,
            role: MessageRole.assistant,
            content: '<think>我先补充询问用户的偏好</think>',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.turnStatus,
            role: MessageRole.system,
            content: 'planner_action_call_tools:ask_user_question',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.assistantQuestionPrompt,
            role: MessageRole.assistant,
            content: '你更偏向 SQLite 还是 ObjectBox？',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 5,
            eventType: ChatEventType.userInteractionResult,
            role: MessageRole.system,
            content: 'User answered AskUserQuestion:\n- Storage: SQLite',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 6,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已记录用户偏好：SQLite',
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastMessages
            .map((message) => '${message.role.name}:${message.text}'),
        [
          'user:帮我确认应该用什么本地存储',
          'assistant:<think>我先补充询问用户的偏好</think>',
          'assistant:你更偏向 SQLite 还是 ObjectBox？',
          'user:User answered AskUserQuestion:\n- Storage: SQLite',
          'assistant:已记录用户偏好：SQLite',
        ],
      );
    });

    test(
        'planNextDecision uses tool-provided model context text for transcript',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: 'ok',
          providerState: {},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(llm: llm);

      await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续处理文件',
        ),
        transcript: [
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已编辑文件：my_hobbies.md',
            payloadJson: const {
              'toolName': 'Edit',
              'status': 'success',
              'summary': '已编辑文件：my_hobbies.md',
              'toolResultText': '已编辑文件：agent/my_hobbies.md',
              'data': {
                'filePath': 'agent/my_hobbies.md',
              },
            },
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastMessages.single.text,
        '已编辑文件：agent/my_hobbies.md',
      );
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
            descriptionForModel: '当用户要求从历史记录找结论时使用。',
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
            descriptionForModel: '当用户明确要求创建本地文件或整文件覆盖时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'file_path': ToolArgumentProperty.string(description: '文件路径'),
                'content': ToolArgumentProperty.string(description: '正文'),
              },
              required: ['file_path', 'content'],
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'search_chat_history');
      expect(decision.toolCalls.single.arguments, {'query': '数据库版本'});
      expect(decision.diagnosticCode, isNull);
      expect(decision.isTerminal, isFalse);
      expect(llm.lastToolOptions, isNotNull);
      expect(llm.lastMessages.single.text, contains('帮我确认数据库版本'));
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
            descriptionForModel: '当用户要求从历史记录找结论时使用。',
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
            descriptionForModel: '当用户明确要求创建本地文件或整文件覆盖时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'file_path': ToolArgumentProperty.string(description: '文件路径'),
                'content': ToolArgumentProperty.string(description: '正文'),
              },
              required: ['file_path', 'content'],
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastProviderStyle, ChatTurnProviderStyle.openaiResponses);
      expect(llm.lastProviderState, containsPair('response_id', 'resp_prev'));
    });

    test(
        'planNextDecision does not fall back to responses continuation from steps',
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
            toolName: 'Write',
            toolArgsJson: const {'file_path': 'notes/old-note.md'},
            status: ChatTurnStepStatus.completed,
            resultSummary: '旧结果',
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastProviderContinuationItems, isEmpty);
    });

    test(
        'planNextDecision builds responses continuation items from transcript when multiple tool calls share one step',
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
            descriptionForModel: '当用户要求从历史记录找结论时使用。',
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
            descriptionForModel: '当需要写文件时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'file_path': ToolArgumentProperty.string(description: '路径'),
              },
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
        transcript: [
          _userEvent(),
          ChatEvent(
            id: 2,
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：搜索聊天记录',
            payloadJson: const {
              'toolName': 'search_chat_history',
              'arguments': {'query': '数据库版本'},
              'providerCallId': 'fc_1',
              'providerResponseId': 'resp_prev',
              'stepId': 1,
            },
          ),
          ChatEvent(
            id: 3,
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：写入文件',
            payloadJson: const {
              'toolName': 'Write',
              'arguments': {'file_path': 'notes/db.md'},
              'providerCallId': 'fc_2',
              'providerResponseId': 'resp_prev',
              'stepId': 1,
            },
          ),
          ChatEvent(
            id: 4,
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已确认数据库版本 7',
            payloadJson: const {
              'summary': '已确认数据库版本 7',
              'data': {'databaseVersion': '7'},
              'providerCallId': 'fc_1',
            },
          ),
          ChatEvent(
            id: 5,
            turnId: 1,
            groupId: 1,
            sequence: 5,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已写入 notes/db.md',
            payloadJson: const {
              'summary': '已写入 notes/db.md',
              'data': {'file_path': 'notes/db.md'},
              'providerCallId': 'fc_2',
            },
          ),
        ],
        steps: [
          ChatTurnStep(
            id: 1,
            turnId: 1,
            stepIndex: 1,
            providerResponseId: 'resp_prev',
            toolName: 'search_chat_history,Write',
            toolArgsJson: {},
            status: ChatTurnStepStatus.completed,
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastProviderContinuationItems, hasLength(2));
      expect(
        llm.lastProviderContinuationItems.first,
        containsPair('call_id', 'fc_1'),
      );
      expect(
        llm.lastProviderContinuationItems.last,
        containsPair('call_id', 'fc_2'),
      );
    });

    test(
        'planNextDecision builds chat completions continuation items for regular tools',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '继续处理',
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
            descriptionForModel: '当用户需要最新外部资料时使用。',
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
          id: 2,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续完成联网搜索结论',
          providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        ),
        transcript: [
          _userEvent(),
          ChatEvent(
            turnId: 2,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：联网搜索',
            payloadJson: const {
              'toolName': 'web_search',
              'arguments': {'query': 'MiniMax API'},
              'providerCallId': 'call_web_1',
            },
          ),
          ChatEvent(
            turnId: 2,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已完成联网搜索',
            payloadJson: const {
              'summary': '已完成联网搜索',
              'data': {'topResult': 'https://example.com/minimax'},
              'providerCallId': 'call_web_1',
            },
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastProviderContinuationItems,
        [
          {
            'type': 'assistant_tool_call',
            'toolCallId': 'call_web_1',
            'toolName': 'web_search',
            'arguments': {
              'query': 'MiniMax API',
            },
          },
          {
            'type': 'tool_result',
            'toolCallId': 'call_web_1',
            'toolName': 'web_search',
            'output':
                '{"status":"success","summary":"已完成联网搜索","data":{"topResult":"https://example.com/minimax"}}',
          },
        ],
      );
    });

    test(
        'planNextDecision builds chat completions ask-user continuation as user answer',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '继续处理',
          providerState: {},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'ask_user_question',
            title: '向用户提问',
            descriptionForModel: '当必须补充关键信息时使用。',
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
      );

      await service.planNextDecision(
        turn: ChatTurn(
          id: 3,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续根据我的偏好给建议',
          providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        ),
        transcript: [
          _userEvent(),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantQuestionPrompt,
            role: MessageRole.assistant,
            content: '请选择存储方案',
            payloadJson: const {
              'toolName': 'ask_user_question',
              'questions': [
                {'id': 'storage', 'question': '请选择存储方案'},
              ],
              'providerCallId': 'call_ask_1',
            },
          ),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.userInteractionResult,
            role: MessageRole.system,
            content: 'User answered AskUserQuestion:\n- Storage: SQLite',
            payloadJson: const {
              'answersByQuestionId': {'storage': 'SQLite'},
              'providerCallId': 'call_ask_1',
            },
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastProviderContinuationItems,
        [
          {
            'type': 'user_interaction_answer',
            'toolCallId': 'call_ask_1',
            'content': 'User answered AskUserQuestion:\n- Storage: SQLite',
          },
        ],
      );
    });

    test(
        'planNextDecision does not fall back to responses ask-user continuation from steps',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '继续处理',
          providerState: {'response_id': 'resp_next'},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(llm: llm);

      await service.planNextDecision(
        turn: ChatTurn(
          id: 3,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续根据我的偏好给建议',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          providerStateJson: const {'response_id': 'resp_prev'},
        ),
        transcript: const [],
        steps: [
          ChatTurnStep(
            id: 4,
            turnId: 3,
            stepIndex: 1,
            providerResponseId: 'resp_prev',
            providerCallId: 'call_ask_1',
            toolName: 'ask_user_question',
            toolArgsJson: {
              'questions': [
                {'id': 'storage', 'question': '请选择存储方案'},
              ],
            },
            status: ChatTurnStepStatus.completed,
            resultSummary: 'user_answered',
            resultJson: {
              'transcriptContent':
                  'User answered AskUserQuestion:\n- Storage: SQLite',
              'answersByQuestionId': {'storage': 'SQLite'},
            },
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastProviderContinuationItems, isEmpty);
    });

    test(
        'planNextDecision deduplicates responses ask-user continuation items from transcript',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '继续处理',
          providerState: {'response_id': 'resp_next'},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(llm: llm);

      await service.planNextDecision(
        turn: ChatTurn(
          id: 3,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续根据我的偏好给建议',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          providerStateJson: const {'response_id': 'resp_prev'},
        ),
        transcript: [
          _userEvent(),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：向用户提问',
            payloadJson: const {
              'toolName': 'ask_user_question',
              'arguments': {
                'questions': [
                  {'id': 'storage', 'question': '请选择存储方案'},
                ],
              },
              'providerCallId': 'call_ask_1',
              'providerResponseId': 'resp_prev',
              'stepId': 8,
            },
          ),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.assistantQuestionPrompt,
            role: MessageRole.assistant,
            content: '请选择存储方案',
            payloadJson: const {
              'questions': [
                {'id': 'storage', 'question': '请选择存储方案'},
              ],
              'agentTurnId': 3,
              'providerCallId': 'call_ask_1',
              'providerResponseId': 'resp_prev',
              'stepId': 8,
            },
          ),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.userInteractionResult,
            role: MessageRole.system,
            content: 'User answered AskUserQuestion:\n- Storage: SQLite',
            payloadJson: const {
              'answersByQuestionId': {'storage': 'SQLite'},
              'providerCallId': 'call_ask_1',
            },
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastProviderContinuationItems,
        [
          {
            'type': 'user_interaction_answer',
            'toolCallId': 'call_ask_1',
            'content': 'User answered AskUserQuestion:\n- Storage: SQLite',
          },
        ],
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
        config: ChatConfig(systemPrompt: ''),
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, contains('当前模型请求失败'));
      expect(decision.assistantMessage, contains('native planner unavailable'));
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
        config: ChatConfig(systemPrompt: ''),
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
              toolName: 'Write',
              arguments: {
                'file_path': 'notes/db-version.md',
                'content': '数据库版本是 7',
              },
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.diagnosticCode, 'planner_unsupported_tool');
      expect(decision.isTerminal, isTrue);
    });

    test(
        'planNextDecision allows duplicate tool calls already completed in the same turn',
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'search_chat_history');
      expect(decision.toolCalls.single.arguments, {
        'query': 'agent loop',
        'maxResults': 5,
      });
      expect(decision.diagnosticCode, isNull);
      expect(decision.isTerminal, isFalse);
    });

    test(
        'planNextDecision preserves assistant text when previous steps used the same tool call',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': 'agent loop', 'maxResults': 5},
              sequence: 0,
            ),
          ],
          assistantMessage: '我先基于现有结果整理一下。',
          providerState: {'response_id': 'resp_keep_text'},
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
            id: 3,
            turnId: 1,
            stepIndex: 1,
            toolName: 'search_chat_history',
            toolArgsJson: {'query': 'agent loop', 'maxResults': 5},
            status: ChatTurnStepStatus.completed,
            resultSummary: '已经找到两条记录',
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'search_chat_history');
      expect(decision.assistantMessage, '我先基于现有结果整理一下。');
      expect(
        decision.providerState,
        containsPair('response_id', 'resp_keep_text'),
      );
      expect(decision.isTerminal, isFalse);
    });

    test(
        'planNextDecision filters duplicate tool calls within the same planner decision',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [
            ModelToolCall(
              toolName: 'Read',
              arguments: {
                'file_path': 'docs/spec.md',
                'offset': 0,
                'limit': 200
              },
              sequence: 0,
            ),
            ModelToolCall(
              toolName: 'Read',
              arguments: {
                'limit': 200,
                'offset': 0,
                'file_path': 'docs/spec.md'
              },
              sequence: 1,
            ),
          ],
          assistantMessage: '我先读取规格说明。',
          providerState: {},
          isTerminal: false,
        ),
      );
      final service = AgentPlannerService(
        llm: llm,
        toolPolicyService: await _createToolPolicyService(),
        availableTools: const [
          ToolDefinition(
            name: 'Read',
            title: '读取文件',
            descriptionForModel: '当已经知道文件路径并需要查看内容时使用。',
            argumentSchema: ToolArgumentSchema(
              properties: {
                'file_path': ToolArgumentProperty.string(description: '路径'),
                'offset': ToolArgumentProperty.integer(description: '起始行'),
                'limit': ToolArgumentProperty.integer(description: '行数'),
              },
              required: ['file_path'],
            ),
          ),
        ],
      );

      final decision = await service.planNextDecision(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '读一下 docs/spec.md',
        ),
        transcript: [_userEvent()],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'Read');
      expect(decision.toolCalls.single.arguments, {
        'file_path': 'docs/spec.md',
        'offset': 0,
        'limit': 200,
      });
      expect(decision.assistantMessage, '我先读取规格说明。');
      expect(decision.isTerminal, isFalse);
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
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(llm.lastToolOptions, isNotNull);
      expect(llm.lastToolOptions!.single.name, 'web_search');
      expect(llm.lastToolOptions!.single.inputSchema['required'], ['query']);
    });

    test(
        'planNextDecision builds anthropic continuation with tool_use followed by tool_result',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '继续处理',
          providerState: {'message_id': 'msg_next'},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(llm: llm);

      await service.planNextDecision(
        turn: ChatTurn(
          id: 3,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '继续完成方案',
          providerStyle: ChatTurnProviderStyle.anthropicMessages,
          providerStateJson: const {'message_id': 'msg_prev'},
        ),
        transcript: [
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '继续完成方案',
          ),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：向用户提问',
            payloadJson: const {
              'toolName': 'ask_user_question',
              'arguments': {
                'questions': [
                  {'id': 'platform', 'question': '目标平台是什么？'},
                ],
              },
              'providerCallId': 'call_function_123',
              'providerResponseId': 'msg_prev',
            },
          ),
          ChatEvent(
            turnId: 3,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: 'user_answered',
            payloadJson: const {
              'summary': 'user_answered',
              'answersByQuestionId': {'platform': 'Android'},
              'data': {
                'answersByQuestionId': {'platform': 'Android'},
              },
              'providerCallId': 'call_function_123',
            },
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastProviderContinuationItems,
        [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'call_function_123',
                'name': 'ask_user_question',
                'input': {
                  'questions': [
                    {'id': 'platform', 'question': '目标平台是什么？'},
                  ],
                },
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'call_function_123',
                'content':
                    '{"status":"success","summary":"user_answered","data":{"answersByQuestionId":{"platform":"Android"}}}',
              },
            ],
          },
        ],
      );
    });

    test(
        'planNextDecision appends anthropic tool_result from transcript when provider content blocks already contain tool_use',
        () async {
      final llm = _NativeDecisionLLM(
        decision: const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '继续处理',
          providerState: {'message_id': 'msg_next'},
          isTerminal: true,
        ),
      );
      final service = AgentPlannerService(llm: llm);

      await service.planNextDecision(
        turn: ChatTurn(
          id: 4,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我看下本地的文件夹都有哪些文件',
          providerStyle: ChatTurnProviderStyle.anthropicMessages,
          providerStateJson: const {
            'message_id': 'msg_prev',
            'content_blocks': [
              {
                'type': 'thinking',
                'thinking': '我要先列出目录。',
                'signature': 'sig_1',
              },
              {
                'type': 'tool_use',
                'id': 'call_function_123',
                'name': 'LS',
                'input': {'path': '.'},
              },
            ],
          },
        ),
        transcript: [
          ChatEvent(
            turnId: 4,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我看下本地的文件夹都有哪些文件',
          ),
          ChatEvent(
            turnId: 4,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：列出目录',
            payloadJson: const {
              'toolName': 'LS',
              'arguments': {'path': '.'},
              'providerCallId': 'call_function_123',
            },
          ),
          ChatEvent(
            turnId: 4,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已列出目录：.',
            payloadJson: const {
              'toolName': 'LS',
              'summary': '已列出目录：.',
              'status': 'success',
              'data': {
                'path': '.',
                'entries': [],
              },
              'providerCallId': 'call_function_123',
            },
          ),
        ],
        steps: const [],
        config: ChatConfig(systemPrompt: ''),
        limits: const AgentLoopLimits(),
      );

      expect(
        llm.lastProviderContinuationItems,
        [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'thinking',
                'thinking': '我要先列出目录。',
                'signature': 'sig_1',
              },
              {
                'type': 'tool_use',
                'id': 'call_function_123',
                'name': 'LS',
                'input': {'path': '.'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'call_function_123',
                'content':
                    '{"status":"success","summary":"已列出目录：.","data":{"path":".","entries":[]}}',
              },
            ],
          },
        ],
      );
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
        config: ChatConfig(systemPrompt: ''),
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
  ChatConfig? lastConfig;
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
    lastConfig = config;
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
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

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
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

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
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

}
