import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/configurable_http_llm.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiProtocolResolver anthropic messages', () {
    test('anthropic messages endpoint resolves and appends correctly', () {
      const resolver = ApiProtocolResolver();

      expect(
        resolver.resolveStyle('https://anthropic.example/v1/messages'),
        ApiStyle.anthropicMessages,
      );
      expect(
        resolver
            .buildRequestUri(
              'https://anthropic.example',
              ApiStyle.anthropicMessages,
            )
            .toString(),
        'https://anthropic.example/v1/messages',
      );
    });
  });

  group('ConfigurableHttpLLM.planTurnDecision', () {
    test('chat completions decision keeps assistant text when tool calls exist',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '我先读取这个页面。',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'fetch_webpage',
                        'arguments': jsonEncode({
                          'url': 'https://example.com/article',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(
            text: '请读取 https://example.com/article',
            role: MessageRole.user,
          ),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'fetch_webpage',
            description: '当用户已经提供 URL 时读取网页内容。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'url': {'type': 'string'},
              },
              'required': ['url'],
            },
          ),
        ],
      );

      expect(decision, isNotNull);
      expect(decision!.assistantMessage, '我先读取这个页面。');
      expect(decision.toolCalls.single.toolName, 'fetch_webpage');
      expect(decision.isTerminal, isFalse);
    });

    test(
        'responses decision keeps assistant text when output mixes message and function_call',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_mixed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '我先搜索一下。',
                  },
                ],
              },
              {
                'type': 'function_call',
                'call_id': 'fc_1',
                'name': 'web_search',
                'arguments': jsonEncode({
                  'query': 'OpenAI 最新发布',
                }),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '帮我查 OpenAI 最新发布', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'web_search',
            description: '当用户需要外部资料或最新信息时联网搜索。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          ),
        ],
      );

      expect(decision, isNotNull);
      expect(decision!.assistantMessage, '我先搜索一下。');
      expect(decision.toolCalls.single.toolName, 'web_search');
      expect(decision.providerState, containsPair('response_id', 'resp_mixed'));
      expect(decision.isTerminal, isFalse);
    });

    test('chat completions decision includes runtime provider metadata',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'search_chat_history',
                        'arguments': jsonEncode({'query': '数据库版本'}),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '查数据库版本', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'search_chat_history',
            description: '搜索聊天历史',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          ),
        ],
      );

      expect(decision, isNotNull);
      expect(
        decision!.providerStyle,
        ChatTurnProviderStyle.openaiChatCompletions,
      );
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.providerState, isEmpty);
      expect(decision.toolCalls.single.providerCallId, 'call_1');
    });

    test('responses decision includes runtime provider metadata', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_123',
            'output': [
              {
                'type': 'function_call',
                'call_id': 'fc_1',
                'name': 'create_reminder',
                'arguments': jsonEncode({'title': '同步数据库版本确认'}),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '今晚 8 点提醒我', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'create_reminder',
            description: '创建提醒',
            inputSchema: {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
              },
              'required': ['title'],
            },
          ),
        ],
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        providerState: const {'response_id': 'resp_prev'},
      );

      expect(decision, isNotNull);
      expect(decision!.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.providerState, containsPair('response_id', 'resp_123'));
      expect(decision.toolCalls.single.providerCallId, 'fc_1');
      expect(client.lastRequestBody?['previous_response_id'], 'resp_prev');
    });

    test(
        'responses decision preserves response_id even when payload store is false',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_unstored',
            'store': false,
            'output': [
              {
                'type': 'function_call',
                'call_id': 'fc_1',
                'name': 'search_chat_history',
                'arguments': jsonEncode({'query': '数据库版本'}),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '查数据库版本', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'search_chat_history',
            description: '搜索聊天历史',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          ),
        ],
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        providerState: const {'response_id': 'resp_prev'},
      );

      expect(decision, isNotNull);
      expect(decision!.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(
          decision.providerState, containsPair('response_id', 'resp_unstored'));
      expect(decision.toolCalls.single.providerCallId, 'fc_1');
      expect(client.lastRequestBody?['previous_response_id'], 'resp_prev');
    });

    test(
        'chat completions decision preserves duplicate multi-tool calls as parsed',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'search_chat_history',
                        'arguments': jsonEncode({
                          'query': '数据库版本',
                          'maxResults': 5,
                        }),
                      },
                    },
                    {
                      'id': 'call_2',
                      'type': 'function',
                      'function': {
                        'name': 'search_chat_history',
                        'arguments': jsonEncode({
                          'query': '数据库版本',
                          'maxResults': 5,
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '查数据库版本并继续下一步', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'search_chat_history',
            description: '搜索聊天历史',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
                'maxResults': {'type': 'number'},
              },
              'required': ['query'],
            },
          ),
        ],
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(2));
      expect(
        decision.toolCalls[0].toolName,
        'search_chat_history',
      );
      expect(
        decision.toolCalls[1].toolName,
        'search_chat_history',
      );
      expect(
        decision.toolCalls[0].arguments,
        decision.toolCalls[1].arguments,
      );
    });

    test('chat completions decision does not carry responses continuation id',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '直接回答',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        providerState: const {'response_id': 'resp_prev'},
      );

      expect(client.lastRequestBody, isNotNull);
      expect(
          client.lastRequestBody!.containsKey('previous_response_id'), isFalse);
    });

    test('responses decision appends function_call_output continuation items',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_456',
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '继续处理完成。',
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        providerState: const {'response_id': 'resp_prev'},
        providerContinuationItems: const [
          {
            'type': 'function_call_output',
            'call_id': 'fc_1',
            'output': '{"status":"success","summary":"已完成"}',
          },
        ],
      );

      final input = client.lastRequestBody?['input'] as List<dynamic>?;
      expect(input, isNotNull);
      expect(input, hasLength(1));
      expect(
        input!.single,
        isA<Map>()
            .having((value) => value['type'], 'type', 'function_call_output')
            .having((value) => value['call_id'], 'call_id', 'fc_1')
            .having(
              (value) => value['output'],
              'output',
              '{"status":"success","summary":"已完成"}',
            ),
      );
      expect(client.lastRequestBody?['previous_response_id'], 'resp_prev');
    });

    test(
        'chat completions decision appends assistant tool call and tool result continuation items',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '继续处理完成。',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        providerContinuationItems: const [
          {
            'type': 'assistant_tool_call',
            'toolCallId': 'call_123',
            'toolName': 'web_search',
            'arguments': {'query': 'MiniMax API'},
          },
          {
            'type': 'tool_result',
            'toolCallId': 'call_123',
            'toolName': 'web_search',
            'output': '{"status":"success","summary":"已完成"}',
          },
        ],
      );

      final messages = client.lastRequestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      expect(messages, hasLength(3));
      expect(messages![1], {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'call_123',
            'type': 'function',
            'function': {
              'name': 'web_search',
              'arguments': '{"query":"MiniMax API"}',
            },
          },
        ],
      });
      expect(messages[2], {
        'role': 'tool',
        'tool_call_id': 'call_123',
        'content': '{"status":"success","summary":"已完成"}',
      });
    });

    test(
        'chat completions decision keeps ask-user continuation as user message',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '建议先用 SQLite。',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        providerContinuationItems: const [
          {
            'type': 'user_interaction_answer',
            'toolCallId': 'call_ask_1',
            'content': 'User answered AskUserQuestion:\n- Storage: SQLite',
          },
        ],
      );

      final messages = client.lastRequestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      expect(messages, hasLength(2));
      expect(messages![1], {
        'role': 'user',
        'content': 'User answered AskUserQuestion:\n- Storage: SQLite',
      });
      expect(
        messages.where((message) => (message as Map)['role'] == 'system'),
        isEmpty,
      );
    });

    test('responses decision uses continuation-only input for ask-user answers',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_ask_next',
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '建议先用 SQLite。',
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        providerState: const {'response_id': 'resp_prev'},
        providerContinuationItems: const [
          {
            'type': 'user_interaction_answer',
            'toolCallId': 'call_ask_1',
            'content': 'User answered AskUserQuestion:\n- Storage: SQLite',
          },
        ],
      );

      final input = client.lastRequestBody?['input'] as List<dynamic>?;
      expect(input, isNotNull);
      expect(input, hasLength(1));
      expect(input!.single, {
        'role': 'user',
        'content': [
          {
            'type': 'input_text',
            'text': 'User answered AskUserQuestion:\n- Storage: SQLite',
          },
        ],
      });
      expect(client.lastRequestBody?['previous_response_id'], 'resp_prev');
    });

    test('responses decision stores planner responses for later continuation',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_store',
            'output': [
              {
                'type': 'function_call',
                'call_id': 'fc_store',
                'name': 'ask_user_question',
                'arguments': jsonEncode({
                  'questions': [
                    {
                      'id': 'q1',
                      'header': '方案',
                      'question': '请选择方案',
                      'options': [
                        {'label': 'A', 'description': '方案 A'},
                      ],
                    },
                  ],
                }),
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '请先问我需要哪个方案', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'ask_user_question',
            description: '当必须向用户补充关键信息时发起结构化提问。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'questions': {'type': 'array'},
              },
              'required': ['questions'],
            },
          ),
        ],
      );

      expect(client.lastRequestBody?['store'], isTrue);
    });

    test('anthropic decision includes runtime provider metadata', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'msg_123',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_123',
                'name': 'web_search',
                'input': {
                  'query': 'Anthropic API',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://anthropic.example/v1/messages',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续搜索', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'web_search',
            description: '搜索外部资料',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          ),
        ],
      );

      expect(decision, isNotNull);
      expect(decision!.providerStyle, ChatTurnProviderStyle.anthropicMessages);
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.providerState, containsPair('message_id', 'msg_123'));
      expect(decision.toolCalls.single.providerCallId, 'toolu_123');
    });

    test('anthropic decision appends tool_result continuation items', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'msg_456',
            'content': [
              {
                'type': 'text',
                'text': '继续处理完成。',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://anthropic.example/v1/messages',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
        providerContinuationItems: const [
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_123',
                'content': '{"status":"success","summary":"已完成"}',
              },
            ],
          },
        ],
      );

      final messages = client.lastRequestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      expect(messages, hasLength(2));
      expect(messages!.last, {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_123',
            'content': '{"status":"success","summary":"已完成"}',
          },
        ],
      });
    });

    test('anthropic continuation preserves prior thinking blocks', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'msg_456',
            'content': [
              {
                'type': 'text',
                'text': '继续处理完成。',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://anthropic.example/v1/messages',
        httpClient: client,
      );

      await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
        providerState: const {
          'message_id': 'msg_123',
          'content_blocks': [
            {
              'type': 'thinking',
              'thinking': '先分析一下工具结果。',
              'signature': 'sig_123',
            },
            {
              'type': 'tool_use',
              'id': 'toolu_123',
              'name': 'web_search',
              'input': {'query': 'latest deepseek docs'},
            },
          ],
        },
        providerContinuationItems: const [
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_123',
                'content': '{"status":"success","summary":"已完成"}',
              },
            ],
          },
        ],
      );

      final messages = client.lastRequestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      expect(messages, hasLength(3));
      expect(messages!.first, {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': '继续',
          },
        ],
      });
      expect(messages[1], {
        'role': 'assistant',
        'content': [
          {
            'type': 'thinking',
            'thinking': '先分析一下工具结果。',
            'signature': 'sig_123',
          },
          {
            'type': 'tool_use',
            'id': 'toolu_123',
            'name': 'web_search',
            'input': {'query': 'latest deepseek docs'},
          },
        ],
      });
      expect(messages[2], {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu_123',
            'content': '{"status":"success","summary":"已完成"}',
          },
        ],
      });
    });
  });

  group('ConfigurableHttpLLM.summarizeConversation', () {
    test('replaces session summary instruction prompt instead of stacking it',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'stable summary',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final summary = await llm.summarizeConversation([
        ChatMessage(
          text: SessionSummaryService.summaryInstructionPrompt,
          role: MessageRole.system,
        ),
        ChatMessage(text: '历史消息', role: MessageRole.user),
      ]);

      expect(summary, 'stable summary');
      final messages = client.lastRequestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      expect(messages, hasLength(2));
      expect(messages!.first['role'], 'system');
      expect((messages.first['content'] as String),
          contains('Summarize and compress the conversation.'));
      expect((messages.first['content'] as String),
          isNot(contains('请将以下会话历史整理为稳定摘要')));
    });

    test('returns empty string when provider summary is empty', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '   ',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final summary = await llm.summarizeConversation([
        ChatMessage(text: '历史消息', role: MessageRole.user),
      ]);

      expect(summary, isEmpty);
    });

    test(
        'responses summary request uses side-model native payload without tools',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_summary',
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'stable summary',
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final summary = await llm.summarizeConversation([
        ChatMessage(text: '历史消息', role: MessageRole.user),
      ]);

      expect(summary, 'stable summary');
      expect(client.lastRequest?.url.path, '/v1/responses');
      expect(client.lastRequestBody?['store'], isTrue);
      expect(client.lastRequestBody?['tools'], isNull);
      expect(client.lastRequestBody?['previous_response_id'], isNull);
    });
  });

  group('ConfigurableHttpLLM.processWebpageContent', () {
    test(
        'responses webpage side-model request uses native payload without tools',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'id': 'resp_webpage',
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '处理后的网页结果',
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final result = await llm.processWebpageContent(
        webpageContent: '网页正文',
        prompt: '提取核心结论',
      );

      expect(result, '处理后的网页结果');
      expect(client.lastRequest?.url.path, '/v1/responses');
      expect(client.lastRequestBody?['store'], isTrue);
      expect(client.lastRequestBody?['tools'], isNull);
      expect(client.lastRequestBody?['previous_response_id'], isNull);
    });
  });
}

Future<ConfigurableHttpLLM> _buildLlm({
  required String baseUrl,
  http.Client? httpClient,
  Duration? plannerRequestTimeout,
  int mainFlowNetworkRetryAttempts = 5,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => LlmLocalDefaults(
      defaultProviderId: 'test-provider',
      defaultModelId: 'gpt-5.4',
      providers: [
        LlmProviderConfig(
          id: 'test-provider',
          name: 'Test Provider',
          apiKey: 'test-key',
          baseUrl: baseUrl,
          models: const [
            LlmProviderModel(id: 'gpt-5.4', name: 'GPT-5.4'),
          ],
        ),
      ],
    ),
  );
  return ConfigurableHttpLLM(
    settingsRepository: repository,
    httpClient: httpClient,
    plannerRequestTimeout: plannerRequestTimeout,
    mainFlowNetworkRetryAttempts: mainFlowNetworkRetryAttempts,
  );
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient({
    required FutureOr<http.Response> Function(http.Request request) handler,
  }) : _handler = handler;

  final FutureOr<http.Response> Function(http.Request request) _handler;

  http.Request? lastRequest;
  Map<String, dynamic>? lastRequestBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final recordedRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    final bytes = await request.finalize().toBytes();
    recordedRequest.bodyBytes = bytes;
    lastRequest = recordedRequest;
    if (bytes.isNotEmpty) {
      lastRequestBody = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }

    final response = await _handler(recordedRequest);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
