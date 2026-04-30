import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
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
    test('rejects empty API key before sending planner request', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response('{}', 200),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        apiKey: '',
      );

      expect(
        () => llm.planTurnDecision(
          messages: [
            ChatMessage(text: '继续', role: MessageRole.user),
          ],
          config: ChatConfig(systemPrompt: ''),
          availableTools: const [],
        ),
        throwsA(isA<Exception>()),
      );
      expect(client.lastRequest, isNull);
    });

    test('returns null when planner response body is empty', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response('', 200),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(decision, isNull);
    });

    test('returns null when planner response payload is not an object',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode([
            {'type': 'message', 'content': 'unexpected'},
          ]),
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
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(decision, isNull);
    });

    test('anthropic streaming planner assembles completed tool call decision',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"write_file"}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":\\"a.txt\\","}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"content\\":\\"hello\\"}"}}\n\n'
          'event: content_block_stop\n'
          'data: {"type":"content_block_stop","index":0}\n\n'
          'data: [DONE]\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/anthropic/v1/messages',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '请写文件', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'write_file',
            description: '写文件',
            inputSchema: {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
                'content': {'type': 'string'},
              },
              'required': ['path', 'content'],
            },
          ),
        ],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'toolu_1');
      expect(decision.toolCalls.single.toolName, 'write_file');
      expect(
        decision.toolCalls.single.arguments,
        {
          'path': 'a.txt',
          'content': 'hello',
        },
      );
      expect(decision.providerStyle, ChatTurnProviderStyle.anthropicMessages);
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.isTerminal, isFalse);
    });

    test('anthropic streaming planner returns null on incomplete tool args',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"write_file"}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":"}}\n\n'
          'event: content_block_stop\n'
          'data: {"type":"content_block_stop","index":0}\n\n'
          'data: [DONE]\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/anthropic/v1/messages',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '请写文件', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'write_file',
            description: '写文件',
            inputSchema: {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
          ),
        ],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNull);
    });

    test('anthropic streaming planner assembles terminal assistant decision',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}\n\n',
            ),
            utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"最终"}}\n\n',
            ),
            utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"答案"}}\n\n',
            ),
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/anthropic/v1/messages',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '直接回答', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '最终答案');
      expect(decision.visibleReasoning, '先分析');
      expect(decision.isTerminal, isTrue);
    });

    test(
        'chat completions streaming planner assembles completed tool call decision',
        () async {
      final firstChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'search_chat_history',
                    'arguments': '{"query":"数据',
                  },
                },
              ],
            },
          },
        ],
      });
      final secondChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'arguments': '库版本"}',
                  },
                },
              ],
            },
          },
        ],
      });
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: $firstChunk\n\n'),
            utf8.encode('data: $secondChunk\n\n'),
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
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

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'call_1');
      expect(decision.toolCalls.single.toolName, 'search_chat_history');
      expect(
        decision.toolCalls.single.arguments,
        {
          'query': '数据库版本',
        },
      );
      expect(
        decision.providerStyle,
        ChatTurnProviderStyle.openaiChatCompletions,
      );
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.isTerminal, isFalse);
    });

    test('responses streaming planner assembles completed tool call decision',
        () async {
      final addedChunk = jsonEncode({
        'type': 'response.output_item.added',
        'response': {'id': 'resp_stream'},
        'item': {
          'type': 'function_call',
          'call_id': 'fc_1',
          'name': 'web_search',
        },
      });
      final firstArgsChunk = jsonEncode({
        'type': 'response.function_call_arguments.delta',
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
        'delta': '{"query":"OpenAI',
      });
      final secondArgsChunk = jsonEncode({
        'type': 'response.function_call_arguments.delta',
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
        'delta': ' 最新发布"}',
      });
      final doneChunk = jsonEncode({
        'type': 'response.function_call_arguments.done',
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
      });
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: $addedChunk\n\n'),
            utf8.encode('data: $firstArgsChunk\n\n'),
            utf8.encode('data: $secondArgsChunk\n\n'),
            utf8.encode('data: $doneChunk\n\n'),
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
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
            description: '联网搜索',
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

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.providerCallId, 'fc_1');
      expect(decision.toolCalls.single.toolName, 'web_search');
      expect(
        decision.toolCalls.single.arguments,
        {
          'query': 'OpenAI 最新发布',
        },
      );
      expect(decision.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.providerState, containsPair('response_id', 'resp_stream'));
      expect(decision.isTerminal, isFalse);
    });

    test(
        'chat completions streaming planner assembles terminal assistant decision',
        () async {
      final firstChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'reasoning_content': '先分析',
              'content': '最终',
            },
          },
        ],
      });
      final secondChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'content': '答案',
            },
          },
        ],
      });
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: $firstChunk\n\n'),
            utf8.encode('data: $secondChunk\n\n'),
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '直接回答', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '最终答案');
      expect(decision.visibleReasoning, '先分析');
      expect(decision.isTerminal, isTrue);
    });

    test('chat completions streaming planner returns null on empty stream',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNull);
    });

    test('responses streaming planner assembles terminal assistant decision',
        () async {
      final firstChunk = jsonEncode({
        'type': 'response.reasoning.delta',
        'response': {'id': 'resp_stream'},
        'delta': '先分析',
      });
      final secondChunk = jsonEncode({
        'type': 'response.output_text.delta',
        'response': {'id': 'resp_stream'},
        'delta': '最终',
      });
      final thirdChunk = jsonEncode({
        'type': 'response.output_text.delta',
        'response': {'id': 'resp_stream'},
        'delta': '答案',
      });
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: $firstChunk\n\n'),
            utf8.encode('data: $secondChunk\n\n'),
            utf8.encode('data: $thirdChunk\n\n'),
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '直接回答', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '最终答案');
      expect(decision.visibleReasoning, '先分析');
      expect(decision.providerState, containsPair('response_id', 'resp_stream'));
      expect(decision.isTerminal, isTrue);
    });

    test('responses streaming planner returns null on empty stream', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNull);
    });

    test(
        'streaming planner does not idle-timeout while chunks keep arriving',
        () async {
      final firstChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'content': '最',
            },
          },
        ],
      });
      final secondChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'content': '终答案',
            },
          },
        ],
      });
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          (() async* {
            yield utf8.encode('data: $firstChunk\n\n');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            yield utf8.encode('data: $secondChunk\n\n');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            yield utf8.encode('data: [DONE]\n');
          })(),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        plannerStreamIdleTimeout: const Duration(milliseconds: 50),
        plannerStreamOverallTimeout: const Duration(milliseconds: 200),
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '直接回答', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(decision, isNotNull);
      expect(decision!.assistantMessage, '最终答案');
      expect(decision.isTerminal, isTrue);
    });

    test('streaming planner fails on idle timeout without new chunks',
        () async {
      final firstChunk = jsonEncode({
        'id': 'chatcmpl_stream',
        'choices': [
          {
            'delta': {
              'content': '最',
            },
          },
        ],
      });
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          (() async* {
            yield utf8.encode('data: $firstChunk\n\n');
            await Future<void>.delayed(const Duration(milliseconds: 80));
            yield utf8.encode('data: [DONE]\n');
          })(),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        plannerStreamIdleTimeout: const Duration(milliseconds: 20),
        plannerStreamOverallTimeout: const Duration(milliseconds: 200),
        mainFlowNetworkRetryAttempts: 1,
      );

      await expectLater(
        () => llm.planTurnDecision(
          messages: [
            ChatMessage(text: '直接回答', role: MessageRole.user),
          ],
          config: ChatConfig(systemPrompt: ''),
          availableTools: const [],
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('streaming planner fails on overall timeout despite incoming chunks',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          (() async* {
            for (var index = 0; index < 10; index += 1) {
              final chunk = jsonEncode({
                'id': 'chatcmpl_stream',
                'choices': [
                  {
                    'delta': {
                      'content': 'a',
                    },
                  },
                ],
              });
              yield utf8.encode('data: $chunk\n\n');
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          })(),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        plannerStreamIdleTimeout: const Duration(milliseconds: 50),
        plannerStreamOverallTimeout: const Duration(milliseconds: 30),
        mainFlowNetworkRetryAttempts: 1,
      );

      await expectLater(
        () => llm.planTurnDecision(
          messages: [
            ChatMessage(text: '直接回答', role: MessageRole.user),
          ],
          config: ChatConfig(systemPrompt: ''),
          availableTools: const [],
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('reports planner retry progress on timeout', () async {
      var attempts = 0;
      final progressEvents = <LlmRetryProgress>[];
      final client = _RecordingHttpClient(
        handler: (request) {
          attempts += 1;
          if (attempts < 3) {
            throw TimeoutException('planner timeout');
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': '重试后成功。',
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
        mainFlowNetworkRetryAttempts: 3,
        retryDelayBuilder: (_) => Duration.zero,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        onRetryScheduled: progressEvents.add,
      );

      expect(attempts, 3);
      expect(decision, isNotNull);
      expect(decision!.assistantMessage, '重试后成功。');
      expect(progressEvents, hasLength(2));
      expect(progressEvents.first.attempt, 1);
      expect(progressEvents.first.maxAttempts, 3);
      expect(progressEvents.last.attempt, 2);
    });

    test('does not emit planner retry progress after final timeout', () async {
      var attempts = 0;
      final progressEvents = <LlmRetryProgress>[];
      final client = _RecordingHttpClient(
        handler: (request) {
          attempts += 1;
          throw TimeoutException('planner timeout');
        },
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        plannerRequestTimeout: const Duration(milliseconds: 10),
        mainFlowNetworkRetryAttempts: 3,
        retryDelayBuilder: (_) => Duration.zero,
      );

      await expectLater(
        () => llm.planTurnDecision(
          messages: [
            ChatMessage(text: '继续', role: MessageRole.user),
          ],
          config: ChatConfig(systemPrompt: ''),
          availableTools: const [],
          onRetryScheduled: progressEvents.add,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 3);
      expect(progressEvents, hasLength(2));
    });

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
            'id': 'chatcmpl_123',
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
      expect(decision.providerState, containsPair('response_id', 'chatcmpl_123'));
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
        'responses decision retries without previous_response_id when provider rejects it',
        () async {
      final requestBodies = <Map<String, dynamic>>[];
      final client = _RecordingHttpClient(
        handler: (request) {
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          requestBodies.add(decoded);
          if (requestBodies.length == 1) {
            return http.Response(
              jsonEncode({
                'error': {
                  'message':
                      'previous_response_id is only supported on Responses WebSocket v2',
                  'type': 'invalid_request_error',
                },
              }),
              400,
              headers: {'content-type': 'application/json'},
              reasonPhrase: 'Bad Request',
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'resp_retry_ok',
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': 'schema_version=10',
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1',
        httpClient: client,
      );

      final decision = await llm.planTurnDecision(
        messages: [
          ChatMessage(text: '继续', role: MessageRole.user),
        ],
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        providerState: const {'response_id': 'resp_prev'},
        providerContinuationItems: const [
          {
            'type': 'assistant_tool_call',
            'toolCallId': 'fc_1',
            'toolName': 'search_chat_history',
            'arguments': {'query': 'database schema drift'},
          },
          {
            'type': 'tool_result',
            'toolCallId': 'fc_1',
            'toolName': 'search_chat_history',
            'output': 'schema_version=10',
          },
        ],
      );

      expect(decision, isNotNull);
      expect((decision!.assistantMessage ?? '').trim(), 'schema_version=10');
      expect(requestBodies, hasLength(2));
      expect(requestBodies.first['previous_response_id'], 'resp_prev');
      expect(requestBodies.last['previous_response_id'], isNull);
      expect(requestBodies.last['input'], [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': '继续',
            },
          ],
        },
        {
          'type': 'function_call',
          'call_id': 'fc_1',
          'name': 'search_chat_history',
          'arguments': '{"query":"database schema drift"}',
        },
        {
          'type': 'function_call_output',
          'call_id': 'fc_1',
          'output': 'schema_version=10',
        },
      ]);
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

    test('injects summary system prompt when input has no system message',
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

      await llm.summarizeConversation([
        ChatMessage(text: '历史消息', role: MessageRole.user),
      ]);

      final messages = client.lastRequestBody?['messages'] as List<dynamic>?;
      expect(messages, isNotNull);
      expect(messages, hasLength(2));
      expect(messages!.first['role'], 'system');
      expect(
        messages.first['content'],
        contains('Summarize and compress the conversation.'),
      );
    });

    test('retries summary request on socket exception before succeeding',
        () async {
      var attempts = 0;
      final client = _RecordingHttpClient(
        handler: (request) {
          attempts += 1;
          if (attempts < 3) {
            throw http.ClientException('SocketException: broken pipe');
          }
          return http.Response(
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
          );
        },
      );

      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        mainFlowNetworkRetryAttempts: 3,
      );

      final summary = await llm.summarizeConversation([
        ChatMessage(text: '历史消息', role: MessageRole.user),
      ]);

      expect(attempts, 3);
      expect(summary, 'stable summary');
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
    test('fails fast when runtime base URL is invalid', () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response('{}', 200),
      );
      final llm = await _buildLlm(
        baseUrl: 'not-a-url',
        httpClient: client,
      );

      expect(
        () => llm.processWebpageContent(
          webpageContent: '网页正文',
          prompt: '提取核心结论',
        ),
        throwsA(isA<Exception>()),
      );
      expect(client.lastRequest, isNull);
    });

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

    test('ignores unexpected tool calls in webpage side-model response',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '网页核心结论',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'web_search',
                        'arguments': jsonEncode({'query': 'unexpected'}),
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

      final result = await llm.processWebpageContent(
        webpageContent: '网页正文',
        prompt: '提取核心结论',
      );

      expect(result, '网页核心结论');
    });
  });
}

Future<ConfigurableHttpLLM> _buildLlm({
  required String baseUrl,
  http.Client? httpClient,
  Duration? plannerRequestTimeout,
  Duration? plannerStreamIdleTimeout,
  Duration? plannerStreamOverallTimeout,
  int mainFlowNetworkRetryAttempts = 5,
  String apiKey = 'test-key',
  String modelId = 'gpt-5.4',
  Duration Function(int attempt)? retryDelayBuilder,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => LlmLocalDefaults(
      defaultProviderId: 'test-provider',
      defaultModelId: modelId,
      providers: [
        LlmProviderConfig(
          id: 'test-provider',
          name: 'Test Provider',
          apiKey: apiKey,
          baseUrl: baseUrl,
          models: [
            LlmProviderModel(id: modelId, name: modelId),
          ],
        ),
      ],
    ),
  );
  return ConfigurableHttpLLM(
    settingsRepository: repository,
    httpClient: httpClient,
    plannerRequestTimeout: plannerRequestTimeout,
    plannerStreamIdleTimeout: plannerStreamIdleTimeout,
    plannerStreamOverallTimeout: plannerStreamOverallTimeout,
    mainFlowNetworkRetryAttempts: mainFlowNetworkRetryAttempts,
    retryDelayBuilder: retryDelayBuilder,
  );
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient({
    required FutureOr<Object> Function(http.Request request) handler,
  }) : _handler = handler;

  final FutureOr<Object> Function(http.Request request) _handler;

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
    if (response is http.StreamedResponse) {
      return http.StreamedResponse(
        response.stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    if (response is http.Response) {
      return http.StreamedResponse(
        Stream<List<int>>.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        request: request,
      );
    }
    throw StateError('Unsupported test response type: ${response.runtimeType}');
  }
}
