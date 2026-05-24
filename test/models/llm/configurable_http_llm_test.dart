import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/adapters/api_style_adapter.dart';
import 'package:ai_chat/models/llm/adapters/provider_capabilities.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/llm/configurable_http_llm.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/llm_cache_usage.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/llm/llm_request_options.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_choice.dart';
import 'package:ai_chat/models/llm/adapters/anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/runtime/protocol_execution_runtime.dart';
import 'package:ai_chat/models/llm/runtime/protocol_request_spec.dart';
import 'package:ai_chat/models/llm/runtime/protocol_runtime_registry.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/utils/logger.dart';
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
          carriers: [
            SyntheticCarrier.user('继续'),
          ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('继续'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('继续'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(decision, isNull);
    });

    test('planner streaming is gated by provider capabilities', () async {
      final runtime = _CountingRuntime(
        executeResult: const ProtocolExecutionResult(
          rawResponseJson: {
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'non-stream response',
                },
              },
            ],
          },
        ),
      );
      final adapter = _FakeAdapter(
        style: ApiStyle.chatCompletions,
        capabilities: const ProviderCapabilities(
          supportsPlannerStreaming: false,
          supportsParallelToolCalls: true,
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        runtimeRegistry: ProtocolRuntimeRegistry(
          runtimes: {
            ApiStyle.chatCompletions: runtime,
            ApiStyle.responses: _CountingRuntime(),
            ApiStyle.anthropicMessages: _CountingRuntime(),
          },
        ),
        adapters: {
          ApiStyle.chatCompletions: adapter,
          ApiStyle.responses: const ResponsesAdapter(),
          ApiStyle.anthropicMessages: const AnthropicMessagesAdapter(),
        },
      );

      final decision = await llm.planTurnDecision(
        carriers: [SyntheticCarrier.user('继续')],
        activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(runtime.executeCalls, 1);
      expect(runtime.streamExecuteCalls, 0);
      expect(decision?.assistantMessage, 'non-stream response');
      expect(adapter.parseDecisionCalls, 1);
    });

    test('planner fallback json is parsed through adapter contract', () async {
      final runtime = _CountingRuntime(
        streamResult: const ProtocolStreamExecutionResult(
          chunks: Stream.empty(),
          nonStreamingFallbackJson: {
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'fallback response',
                },
              },
            ],
          },
        ),
      );
      final adapter = _FakeAdapter(
        style: ApiStyle.chatCompletions,
        capabilities: const ProviderCapabilities(
          supportsPlannerStreaming: true,
          supportsParallelToolCalls: true,
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        runtimeRegistry: ProtocolRuntimeRegistry(
          runtimes: {
            ApiStyle.chatCompletions: runtime,
            ApiStyle.responses: _CountingRuntime(),
            ApiStyle.anthropicMessages: _CountingRuntime(),
          },
        ),
        adapters: {
          ApiStyle.chatCompletions: adapter,
          ApiStyle.responses: const ResponsesAdapter(),
          ApiStyle.anthropicMessages: const AnthropicMessagesAdapter(),
        },
      );

      final decision = await llm.planTurnDecision(
        carriers: [SyntheticCarrier.user('继续')],
        activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(runtime.executeCalls, 0);
      expect(runtime.streamExecuteCalls, 1);
      expect(adapter.parseDecisionCalls, 1);
      expect(decision?.assistantMessage, 'fallback response');
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
        carriers: [
          SyntheticCarrier.user('请写文件'),
        ],
          activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
          currentTurnRunning: false,
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
      expect(client.lastRequestBody?['thinking'], const {'type': 'disabled'});
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
      expect(
        decision.providerState['content_blocks'],
        [
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'write_file',
            'input': {
              'path': 'a.txt',
              'content': 'hello',
            },
          },
        ],
      );
      expect(decision.providerStyle, ChatTurnProviderStyle.anthropicMessages);
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.isTerminal, isFalse);
    });

    test('anthropic streaming planner keeps decision on incomplete tool args',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}\n\n'
              'event: content_block_start\n'
              'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"write_file"}}\n\n'
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":"}}\n\n'
              'event: content_block_stop\n'
              'data: {"type":"content_block_stop","index":0}\n\n'
              'data: [DONE]\n',
            ),
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
        carriers: [
          SyntheticCarrier.user('请写文件'),
        ],
          activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
          currentTurnRunning: false,
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
      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.visibleReasoning, '先分析');
    });

    test(
        'anthropic streaming planner keeps decision when tool args end with trailing garbage',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}\n\n'
              'event: content_block_start\n'
              'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"create_artifact"}}\n\n'
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"id\\":\\"china-food-ranking\\",\\"type\\":\\"html\\",\\"title\\":\\"中国美食排行\\",\\"source\\":\\"<div>ok</div>\\"}"}}\n\n'
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"<unexpected-tail>"}}\n\n'
              'event: content_block_stop\n'
              'data: {"type":"content_block_stop","index":0}\n\n'
              'data: [DONE]\n',
            ),
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
        carriers: [
          SyntheticCarrier.user('请创建美食页面'),
        ],
          activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
          currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'create_artifact',
            description: '创建 artifact',
            inputSchema: {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'type': {'type': 'string'},
                'title': {'type': 'string'},
                'source': {'type': 'string'},
              },
              'required': ['id', 'type', 'title', 'source'],
            },
          ),
        ],
      );

      expect(client.lastRequestBody?['stream'], isTrue);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.visibleReasoning, '先分析');
    });

    test('anthropic streaming planner should tolerate ping keepalive chunks',
        () async {
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          (() async* {
            yield utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}\n\n',
            );
            await Future<void>.delayed(const Duration(milliseconds: 10));
            yield utf8.encode('event: ping\ndata: {"type":"ping"}\n\n');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            yield utf8.encode('event: ping\ndata: {"type":"ping"}\n\n');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            yield utf8.encode(
              'event: content_block_start\n'
              'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"create_artifact"}}\n\n',
            );
            yield utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"id\\":\\"demo\\",\\"type\\":\\"html\\",\\"title\\":\\"Demo\\",\\"source\\":\\"<div>ok</div>\\"}"}}\n\n',
            );
            yield utf8.encode(
              'event: content_block_stop\n'
              'data: {"type":"content_block_stop","index":0}\n\n',
            );
            yield utf8.encode('data: [DONE]\n');
          })(),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/anthropic/v1/messages',
        httpClient: client,
        plannerStreamIdleTimeout: const Duration(milliseconds: 20),
        plannerStreamOverallTimeout: const Duration(seconds: 1),
      );

      final decision = await llm.planTurnDecision(
        carriers: [
          SyntheticCarrier.user('请创建 artifact'),
        ],
          activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
          currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [
          PlannerToolOption(
            name: 'create_artifact',
            description: '创建 artifact',
            inputSchema: {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'type': {'type': 'string'},
                'title': {'type': 'string'},
                'source': {'type': 'string'},
              },
              'required': ['id', 'type', 'title', 'source'],
            },
          ),
        ],
      );

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'create_artifact');
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
        carriers: [
          SyntheticCarrier.user('直接回答'),
        ],
          activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
          currentTurnRunning: false,
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
                  'index': 0,
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
                  'index': 0,
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
        carriers: [
          SyntheticCarrier.user('查数据库版本'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        'output_index': 0,
        'response': {'id': 'resp_stream'},
        'item': {
          'type': 'function_call',
          'call_id': 'fc_1',
          'name': 'web_search',
        },
      });
      final firstArgsChunk = jsonEncode({
        'type': 'response.function_call_arguments.delta',
        'output_index': 0,
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
        'delta': '{"query":"OpenAI',
      });
      final secondArgsChunk = jsonEncode({
        'type': 'response.function_call_arguments.delta',
        'output_index': 0,
        'response': {'id': 'resp_stream'},
        'call_id': 'fc_1',
        'name': 'web_search',
        'delta': ' 最新发布"}',
      });
      final doneChunk = jsonEncode({
        'type': 'response.function_call_arguments.done',
        'output_index': 0,
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
        carriers: [
          SyntheticCarrier.user('帮我查 OpenAI 最新发布'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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

    test('records trace events for non-stream planner requests', () async {
      final collected = <Map<String, dynamic>>[];
      final runtime = _CountingRuntime(
        executeResult: const ProtocolExecutionResult(
          rawResponseJson: {
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '直接回答',
                },
              },
            ],
          },
          cacheUsage: LlmCacheUsage(
            inputTokens: 12,
            outputTokens: 4,
            cachedInputTokens: 8,
          ),
        ),
      );
      final adapter = _FakeAdapter(
        style: ApiStyle.chatCompletions,
        capabilities: const ProviderCapabilities(
          supportsPlannerStreaming: false,
          supportsParallelToolCalls: true,
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        runtimeRegistry: ProtocolRuntimeRegistry(
          runtimes: {
            ApiStyle.chatCompletions: runtime,
            ApiStyle.responses: _CountingRuntime(),
            ApiStyle.anthropicMessages: _CountingRuntime(),
          },
        ),
        adapters: {
          ApiStyle.chatCompletions: adapter,
          ApiStyle.responses: const ResponsesAdapter(),
          ApiStyle.anthropicMessages: const AnthropicMessagesAdapter(),
        },
        traceEmitter: (tag, message, {level = LogLevel.info, data}) {
          collected.add({
            'tag': tag,
            'message': message,
            'level': level.name,
            if (data != null) 'data': data,
          });
        },
      );

      final decision = await llm.planTurnDecision(
        carriers: [
          SyntheticCarrier.user('直接回答'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(decision, isNotNull);
      final done = collected.lastWhere(
        (entry) => entry['message'] == 'llm.request.done',
      );
      expect(done['data'], containsPair('cachedInputTokens', 8));
    });

    test('records trace events for streaming planner requests', () async {
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
      final collected = <Map<String, dynamic>>[];
      final client = _RecordingHttpClient(
        handler: (request) => http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('data: $firstChunk\n\n'),
            utf8.encode('data: [DONE]\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://planner.example/v1/chat/completions',
        httpClient: client,
        traceEmitter: (tag, message, {level = LogLevel.info, data}) {
          collected.add({
            'tag': tag,
            'message': message,
            'level': level.name,
            if (data != null) 'data': data,
          });
        },
      );

      final decision = await llm.planTurnDecision(
        carriers: [
          SyntheticCarrier.user('直接回答'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(decision, isNotNull);
      expect(
        collected.where((entry) => entry['message'] == 'llm.request.start'),
        isNotEmpty,
      );
      expect(
        collected.where((entry) => entry['message'] == 'llm.first_chunk'),
        isNotEmpty,
      );
      expect(
        collected.where((entry) => entry['message'] == 'llm.request.done'),
        isNotEmpty,
      );
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
        carriers: [
          SyntheticCarrier.user('直接回答'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('继续'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('直接回答'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('继续'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('直接回答'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
          carriers: [
            SyntheticCarrier.user('直接回答'),
          ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
          carriers: [
            SyntheticCarrier.user('直接回答'),
          ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('继续'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
          carriers: [
            SyntheticCarrier.user('继续'),
          ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: const [
          SyntheticCarrier.user('请读取 https://example.com/article'),
        ],
        activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('帮我查 OpenAI 最新发布'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('查数据库版本'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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
        carriers: [
          SyntheticCarrier.user('今晚 8 点提醒我'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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
      );

      expect(decision, isNotNull);
      expect(decision!.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(decision.modelName, 'gpt-5.4');
      expect(decision.providerState, containsPair('response_id', 'resp_123'));
      expect(decision.toolCalls.single.providerCallId, 'fc_1');
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
        carriers: [
          SyntheticCarrier.user('查数据库版本'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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
      expect(decision!.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(
          decision.providerState, containsPair('response_id', 'resp_unstored'));
      expect(decision.toolCalls.single.providerCallId, 'fc_1');
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
        carriers: [
          SyntheticCarrier.user('查数据库版本并继续下一步'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
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

    test('chat completions decision relies on transcript replay only',
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
        carriers: [
          SyntheticCarrier.user('继续'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiChatCompletions,
          currentTurnRunning: false,
        config: ChatConfig(systemPrompt: ''),
        availableTools: const [],
      );

      expect(client.lastRequestBody, isNotNull);
      expect(
          client.lastRequestBody!.containsKey('previous_response_id'), isFalse);
    });

    test('responses decision keeps provider storage disabled for planner calls',
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
        carriers: [
          SyntheticCarrier.user('请先问我需要哪个方案'),
        ],
          activeApiStyle: ChatTurnProviderStyle.openaiResponses,
          currentTurnRunning: false,
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

      expect(client.lastRequestBody?['store'], isFalse);
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
        carriers: [
          SyntheticCarrier.user('继续搜索'),
        ],
          activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
          currentTurnRunning: false,
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

    test('anthropic planner streaming uses runtime registry dispatch',
        () async {
      final runtime = _CountingRuntime(
        streamResult: const ProtocolStreamExecutionResult(
          chunks: Stream.empty(),
          nonStreamingFallbackJson: {
            'id': 'msg_123',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_123',
                'name': 'web_search',
                'input': {'query': 'Anthropic API'},
              },
            ],
          },
        ),
      );
      final llm = await _buildLlm(
        baseUrl: 'https://anthropic.example/v1/messages',
        runtimeRegistry: ProtocolRuntimeRegistry(
          runtimes: {
            ApiStyle.chatCompletions: _CountingRuntime(),
            ApiStyle.responses: _CountingRuntime(),
            ApiStyle.anthropicMessages: runtime,
          },
        ),
      );

      final decision = await llm.planTurnDecision(
        carriers: [
          SyntheticCarrier.user('继续搜索'),
        ],
        activeApiStyle: ChatTurnProviderStyle.anthropicMessages,
        currentTurnRunning: false,
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

      expect(runtime.streamExecuteCalls, 1);
      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(decision.toolCalls.single.toolName, 'web_search');
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
      expect(client.lastRequestBody?['store'], isFalse);
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
      expect(client.lastRequestBody?['store'], isFalse);
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
  ProtocolRuntimeRegistry? runtimeRegistry,
  Map<ApiStyle, ApiStyleAdapter>? adapters,
  Duration? plannerRequestTimeout,
  Duration? plannerStreamIdleTimeout,
  Duration? plannerStreamOverallTimeout,
  int mainFlowNetworkRetryAttempts = 5,
  String apiKey = 'test-key',
  String modelId = 'gpt-5.4',
  void Function(
    String tag,
    String message, {
    LogLevel level,
    Map<String, dynamic>? data,
  })? traceEmitter,
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
    runtimeRegistry: runtimeRegistry,
    adapters: adapters,
    plannerRequestTimeout: plannerRequestTimeout,
    plannerStreamIdleTimeout: plannerStreamIdleTimeout,
    plannerStreamOverallTimeout: plannerStreamOverallTimeout,
    mainFlowNetworkRetryAttempts: mainFlowNetworkRetryAttempts,
    traceEmitter: traceEmitter,
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

class _CountingRuntime extends ProtocolExecutionRuntime {
  _CountingRuntime({
    this.executeResult = const ProtocolExecutionResult(rawResponseJson: {}),
    this.streamResult = const ProtocolStreamExecutionResult(
      chunks: Stream.empty(),
    ),
  });

  int executeCalls = 0;
  int streamExecuteCalls = 0;
  final ProtocolExecutionResult executeResult;
  final ProtocolStreamExecutionResult streamResult;

  @override
  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    executeCalls += 1;
    return executeResult;
  }

  @override
  Future<ProtocolStreamExecutionResult> streamExecute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration idleTimeout,
    required Duration overallTimeout,
  }) async {
    streamExecuteCalls += 1;
    return streamResult;
  }
}

class _FakeAdapter extends ApiStyleAdapter {
  _FakeAdapter({
    required this.style,
    required this.capabilities,
  });

  @override
  final ApiStyle style;

  @override
  final ProviderCapabilities capabilities;

  int parseDecisionCalls = 0;

  @override
  Map<String, String> buildHeaders(LLMConfig runtimeConfig) => const {};

  @override
  ProtocolRequestSpec buildChatRequestSpec({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    required LLMConfig runtimeConfig,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    return const JsonProtocolRequestSpec(payload: {}, headers: {});
  }

  @override
  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    return const {};
  }

  @override
  ProtocolRequestSpec buildPlannerRequestSpecFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    required LLMConfig runtimeConfig,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    return const JsonProtocolRequestSpec(payload: {}, headers: {});
  }

  @override
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    return const {};
  }

  @override
  String extractNonStreamText(Map<String, dynamic> payload) => '';

  @override
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  ) {
    return null;
  }

  @override
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    return null;
  }

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) => null;

  @override
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    parseDecisionCalls += 1;
    final choices = payload['choices'];
    if (choices is List &&
        choices.isNotEmpty &&
        choices.first is Map &&
        (choices.first as Map)['message'] is Map) {
      final message = (choices.first as Map)['message'] as Map;
      final content = message['content']?.toString();
      if (content != null && content.isNotEmpty) {
        return ModelTurnDecision(
          toolCalls: const [],
          assistantMessage: content,
          providerState: const {},
          isTerminal: true,
        );
      }
    }
    return null;
  }
}
