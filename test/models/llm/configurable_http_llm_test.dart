import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/configurable_http_llm.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigurableHttpLLM.planNextToolChoice', () {
    test('chat completions payload includes planner tools and parses tool call',
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

      final choice = await llm.planNextToolChoice(
        messages: [
          ChatMessage(
            text: '请读取 https://example.com/article',
            role: MessageRole.user,
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'fetch_webpage',
            description: '当用户已经提供 URL 时读取网页内容。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'url': {
                  'type': 'string',
                  'description': '要读取的网页链接',
                },
              },
              'required': ['url'],
            },
          ),
        ],
      );

      expect(choice, isNotNull);
      expect(choice!.isToolCall, isTrue);
      expect(
        choice,
        isA<PlannerToolChoice>()
            .having((value) => value.toolName, 'toolName', 'fetch_webpage')
            .having(
          (value) => value.arguments,
          'arguments',
          {'url': 'https://example.com/article'},
        ),
      );
      expect(client.lastRequest?.url.path, '/v1/chat/completions');
      expect(client.lastRequestBody?['stream'], isFalse);
      expect(client.lastRequestBody?['tool_choice'], 'auto');
      expect(client.lastRequestBody?['parallel_tool_calls'], isFalse);
      expect(client.lastRequestBody?['messages'], [
        {
          'role': 'user',
          'content': '请读取 https://example.com/article',
        },
      ]);
      expect(client.lastRequestBody?['tools'], [
        {
          'type': 'function',
          'function': {
            'name': 'fetch_webpage',
            'description': '当用户已经提供 URL 时读取网页内容。',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {
                  'type': 'string',
                  'description': '要读取的网页链接',
                },
              },
              'required': ['url'],
            },
          },
        },
      ]);
    });

    test('chat completions parser falls back to direct response content',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '我已经有足够信息，可以直接回答用户。',
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

      final choice = await llm.planNextToolChoice(
        messages: [
          ChatMessage(text: '解释一下 tool calling', role: MessageRole.user),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        availableTools: const [],
      );

      expect(choice, isNotNull);
      expect(choice!.isRespond, isTrue);
      expect(choice.response, '我已经有足够信息，可以直接回答用户。');
    });

    test('responses payload includes planner tools and parses function call',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'web_search',
                'arguments': jsonEncode({
                  'query': 'Claude Code tool use design',
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

      final choice = await llm.planNextToolChoice(
        messages: [
          ChatMessage(
            text: '帮我查 Claude Code 的 tool use 设计',
            role: MessageRole.user,
          ),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'web_search',
            description: '当用户需要外部资料或最新信息时联网搜索。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': '短而具体的搜索词',
                },
              },
              'required': ['query'],
            },
          ),
        ],
      );

      expect(choice, isNotNull);
      expect(choice!.isToolCall, isTrue);
      expect(choice.toolName, 'web_search');
      expect(choice.arguments, {
        'query': 'Claude Code tool use design',
      });
      expect(client.lastRequest?.url.path, '/v1/responses');
      expect(client.lastRequestBody?['stream'], isFalse);
      expect(client.lastRequestBody?['tool_choice'], 'auto');
      expect(client.lastRequestBody?['parallel_tool_calls'], isFalse);
      expect(client.lastRequestBody?['store'], isFalse);
      expect(client.lastRequestBody?['input'], [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': '帮我查 Claude Code 的 tool use 设计',
            },
          ],
        },
      ]);
      expect(client.lastRequestBody?['tools'], [
        {
          'type': 'function',
          'name': 'web_search',
          'description': '当用户需要外部资料或最新信息时联网搜索。',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': '短而具体的搜索词',
              },
            },
            'required': ['query'],
          },
        },
      ]);
    });

    test('responses parser extracts direct assistant response', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '不需要调用工具，直接回答即可。',
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

      final choice = await llm.planNextToolChoice(
        messages: [
          ChatMessage(text: '什么是 planner prompt', role: MessageRole.user),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        availableTools: const [],
      );

      expect(choice, isNotNull);
      expect(choice!.isRespond, isTrue);
      expect(choice.response, '不需要调用工具，直接回答即可。');
    });

    test('returns null when structured planner response is not valid json',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          '',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final choice = await llm.planNextToolChoice(
        messages: [
          ChatMessage(text: '帮我查 Claude 最新进展', role: MessageRole.user),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'web_search',
            description: '当用户需要外部资料或最新信息时联网搜索。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': '短而具体的搜索词',
                },
              },
              'required': ['query'],
            },
          ),
        ],
      );

      expect(choice, isNull);
    });

    test('returns null quickly when structured planner request times out',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(
            jsonEncode({'output': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
        plannerRequestTimeout: const Duration(milliseconds: 20),
      );

      final stopwatch = Stopwatch()..start();
      final choice = await llm.planNextToolChoice(
        messages: [
          ChatMessage(text: '帮我查 Claude 最新进展', role: MessageRole.user),
        ],
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'web_search',
            description: '当用户需要外部资料或最新信息时联网搜索。',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': '短而具体的搜索词',
                },
              },
              'required': ['query'],
            },
          ),
        ],
      );
      stopwatch.stop();

      expect(choice, isNull);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('ConfigurableHttpLLM.planNextAction', () {
    test('fails quickly when legacy planner request times out', () async {
      final client = _RecordingHttpClient(
        handler: (request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '{"action":"respond","response":"ok"}'
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        plannerRequestTimeout: const Duration(milliseconds: 20),
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(
        llm.planNextAction(
          messages: [
            ChatMessage(text: '帮我查 Claude 最新进展', role: MessageRole.user),
          ],
          config: ChatConfig(useReasoning: false, systemPrompt: ''),
        ),
        throwsException,
      );
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('ConfigurableHttpLLM.planTurnDecision', () {
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
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
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

    test('chat completions decision preserves duplicate multi-tool calls as parsed',
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
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
  });
}

Future<ConfigurableHttpLLM> _buildLlm({
  required String baseUrl,
  http.Client? httpClient,
  Duration? plannerRequestTimeout,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => LlmLocalDefaults(
      apiKey: 'test-key',
      baseUrl: baseUrl,
      model: 'gpt-5.4',
    ),
  );
  return ConfigurableHttpLLM(
    settingsRepository: repository,
    httpClient: httpClient,
    plannerRequestTimeout: plannerRequestTimeout,
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
