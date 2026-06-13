import 'dart:convert';

import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/runtime/openai_responses_runtime.dart';
import 'package:ai_chat/models/llm/runtime/protocol_request_spec.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as oai;

void main() {
  test('executes responses request through dedicated runtime', () async {
    final runtime = OpenAiResponsesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'id': 'resp_1',
            'object': 'response',
            'status': 'completed',
            'model': 'gpt-5.4',
            'output': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await runtime.execute(
      requestSpec: ResponsesRequestSpec(
        request: oai.CreateResponseRequest(
          model: 'gpt-5.4',
          input: const oai.ResponseInput.text('hello'),
        ),
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://responses.example/v1',
        model: 'gpt-5.4',
      ),
      timeout: const Duration(seconds: 1),
    );

    expect(result.rawResponseJson['id'], 'resp_1');
  });

  test(
    'executes non-stream responses through sdk after normalizing provider message shape',
    () async {
      final runtime = OpenAiResponsesRuntime(
        httpClient: _FakeHttpClient(
          response: http.Response(
            jsonEncode({
              'id': 'resp_provider_shape',
              'object': 'response',
              'status': 'completed',
              'model': 'gpt-5.4',
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': 'provider-compatible raw response',
                    },
                  ],
                },
              ],
              'usage': {
                'input_tokens': 12,
                'input_tokens_details': {'cached_tokens': 8},
                'output_tokens': 4,
                'total_tokens': 16,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final result = await runtime.execute(
        requestSpec: ResponsesRequestSpec(
          request: oai.CreateResponseRequest(
            model: 'gpt-5.4',
            input: const oai.ResponseInput.text('hello'),
          ),
        ),
        runtimeConfig: const LLMConfig(
          apiKey: 'k',
          apiUrl: 'https://responses.example/v1',
          model: 'gpt-5.4',
        ),
        timeout: const Duration(seconds: 1),
      );

      expect(result.rawResponseJson['id'], 'resp_provider_shape');
      final output = result.rawResponseJson['output'] as List<dynamic>;
      final message = output.single as Map<String, dynamic>;
      expect(message['id'], isNotEmpty);
      expect(message['role'], 'assistant');
      expect(message['status'], 'completed');
      expect(result.cacheUsage?.cachedInputTokens, 8);
    },
  );

  test('streams responses preview events through typed event adapter', () async {
    final capturedRequests = <oai.CreateResponseRequest>[];
    final runtime = OpenAiResponsesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          'not typed events',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
      streamRequestExecutor: ({required request, required streamedResponse}) {
        capturedRequests.add(request);
        return Stream<oai.ResponseStreamEvent>.fromIterable([
          oai.ResponseStreamEvent.fromJson({
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_1',
              'name': 'web_search',
              'arguments': '',
            },
          }),
          oai.ResponseStreamEvent.fromJson({
            'type': 'response.function_call_arguments.delta',
            'output_index': 0,
            'call_id': 'call_1',
            'name': 'web_search',
            'delta': '{"query":"flutter"}',
          }),
          oai.ResponseStreamEvent.fromJson({
            'type': 'response.function_call_arguments.done',
            'output_index': 0,
            'call_id': 'call_1',
            'name': 'web_search',
            'arguments': '{"query":"flutter"}',
          }),
        ]);
      },
    );

    final result = await runtime.streamExecute(
      requestSpec: ResponsesRequestSpec(
        request: oai.CreateResponseRequest(
          model: 'gpt-5.4',
          input: const oai.ResponseInput.text('search'),
          store: false,
        ),
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://responses.example/v1',
        model: 'gpt-5.4',
      ),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 3),
    );

    final events = await result.events.toList();

    expect(capturedRequests, hasLength(1));
    expect(capturedRequests.single.toJson()['stream'], isNot(true));
    expect(
      events.any(
        (event) =>
            event is StreamingContentBlockStartEvent &&
            event.toolUseId == 'call_1' &&
            event.toolName == 'web_search',
      ),
      isTrue,
    );
    expect(
      events.any(
        (event) =>
            event is StreamingContentBlockDeltaEvent &&
            event.deltaType == StreamingContentDeltaType.inputJson &&
            event.value == '{"query":"flutter"}',
      ),
      isTrue,
    );
    expect(
      events.any(
        (event) =>
            event is StreamingContentBlockStopEvent,
      ),
      isTrue,
    );
    expect(events.last, isA<StreamingMessageStopEvent>());
  });

  test('falls back to non-stream json when responses stream returns json body',
      () async {
    var streamExecutorCalled = false;
    final runtime = OpenAiResponsesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'id': 'resp_fallback',
            'object': 'response',
            'status': 'completed',
            'output': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      streamRequestExecutor: ({required request, required streamedResponse}) {
        streamExecutorCalled = true;
        return const Stream<oai.ResponseStreamEvent>.empty();
      },
    );

    final result = await runtime.streamExecute(
      requestSpec: ResponsesRequestSpec(
        request: oai.CreateResponseRequest(
          model: 'gpt-5.4',
          input: const oai.ResponseInput.text('fallback'),
        ),
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://responses.example/v1',
        model: 'gpt-5.4',
      ),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 3),
    );

    expect(await result.events.toList(), isEmpty);
    expect(streamExecutorCalled, isFalse);
    expect(result.nonStreamingFallbackJson?['id'], 'resp_fallback');
    expect(result.nonStreamingFallbackJson?['_http_status'], 200);
  });

  test('preserves http error metadata when responses stream returns json error',
      () async {
    final runtime = OpenAiResponsesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'error': {
              'message': 'Invalid token',
              'type': 'new_api_error',
            },
          }),
          401,
          headers: {'content-type': 'application/json'},
          reasonPhrase: 'Unauthorized',
        ),
      ),
    );

    final result = await runtime.streamExecute(
      requestSpec: ResponsesRequestSpec(
        request: oai.CreateResponseRequest(
          model: 'gpt-5.4',
          input: const oai.ResponseInput.text('fallback'),
        ),
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://responses.example/v1',
        model: 'gpt-5.4',
      ),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 3),
    );

    expect(await result.events.toList(), isEmpty);
    expect(result.nonStreamingFallbackJson?['_http_status'], 401);
    expect(result.nonStreamingFallbackJson?['_http_reason'], 'Unauthorized');
    expect(
      (result.nonStreamingFallbackJson?['error'] as Map<String, dynamic>)['message'],
      'Invalid token',
    );
  });

  test(
    'keeps preview deltas when response.completed payload is provider-incompatible',
    () async {
      final runtime = OpenAiResponsesRuntime(
        httpClient: _FakeHttpClient(
          response: http.Response(
            [
              'data: ${jsonEncode({
                'type': 'response.output_text.delta',
                'response': {'id': 'resp_partial'},
                'output_index': 0,
                'content_index': 0,
                'delta': 'Hello',
              })}\n',
              '\n',
              'data: ${jsonEncode({
                'type': 'response.completed',
                'response': {
                  'id': 'resp_partial',
                  'object': 'response',
                  'created_at': 123,
                  'status': 'completed',
                  'output': null,
                },
              })}\n',
              '\n',
              'data: [DONE]\n',
            ].join(),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          ),
        ),
      );

      final result = await runtime.streamExecute(
        requestSpec: ResponsesRequestSpec(
          request: oai.CreateResponseRequest(
            model: 'gpt-5.4',
            input: const oai.ResponseInput.text('hello'),
          ),
        ),
        runtimeConfig: const LLMConfig(
          apiKey: 'k',
          apiUrl: 'https://responses.example/v1',
          model: 'gpt-5.4',
        ),
        idleTimeout: const Duration(seconds: 1),
        overallTimeout: const Duration(seconds: 3),
      );

      final events = await result.events.toList();
      expect(
        events.whereType<StreamingContentBlockDeltaEvent>().map((e) => e.value),
        contains('Hello'),
      );
      expect(events.last, isA<StreamingMessageStopEvent>());
    },
  );

  test(
    'keeps preview deltas when response.completed output item misses strict sdk fields',
    () async {
      final runtime = OpenAiResponsesRuntime(
        httpClient: _FakeHttpClient(
          response: http.Response(
            [
              'data: ${jsonEncode({
                'type': 'response.output_text.delta',
                'response': {'id': 'resp_partial'},
                'output_index': 0,
                'content_index': 0,
                'delta': 'Hello',
              })}\n',
              '\n',
              'data: ${jsonEncode({
                'type': 'response.completed',
                'response': {
                  'id': 'resp_partial',
                  'object': 'response',
                  'created_at': 123,
                  'status': 'completed',
                  'output': [
                    {
                      'id': 'msg_partial',
                      'type': 'message',
                      'status': 'completed',
                      // Real providers have been observed to omit strict SDK
                      // fields like role/content on response.completed while
                      // earlier incremental events remain usable.
                      'role': null,
                      'content': null,
                    },
                  ],
                },
              })}\n',
              '\n',
              'data: [DONE]\n',
            ].join(),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          ),
        ),
      );

      final result = await runtime.streamExecute(
        requestSpec: ResponsesRequestSpec(
          request: oai.CreateResponseRequest(
            model: 'gpt-5.4',
            input: const oai.ResponseInput.text('hello'),
          ),
        ),
        runtimeConfig: const LLMConfig(
          apiKey: 'k',
          apiUrl: 'https://responses.example/v1',
          model: 'gpt-5.4',
        ),
        idleTimeout: const Duration(seconds: 1),
        overallTimeout: const Duration(seconds: 3),
      );

      final events = await result.events.toList();
      expect(
        events.whereType<StreamingContentBlockDeltaEvent>().map((e) => e.value),
        contains('Hello'),
      );
      expect(events.last, isA<StreamingMessageStopEvent>());
    },
  );

  test(
    'normalizes response.failed payload when provider omits strict sdk integer fields',
    () async {
      final runtime = OpenAiResponsesRuntime(
        httpClient: _FakeHttpClient(
          response: http.Response(
            [
              'data: ${jsonEncode({
                'type': 'response.failed',
                'response': {
                  'id': 'resp_failed',
                  'object': 'response',
                  'model': 'gpt-5.4',
                  'status': 'failed',
                  'output': [],
                  'error': {
                    'code': 'rate_limit_exceeded',
                    'message': 'retry later',
                  },
                },
              })}\n',
              '\n',
              'data: [DONE]\n',
            ].join(),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          ),
        ),
      );

      final result = await runtime.streamExecute(
        requestSpec: ResponsesRequestSpec(
          request: oai.CreateResponseRequest(
            model: 'gpt-5.4',
            input: const oai.ResponseInput.text('hello'),
          ),
        ),
        runtimeConfig: const LLMConfig(
          apiKey: 'k',
          apiUrl: 'https://responses.example/v1',
          model: 'gpt-5.4',
        ),
        idleTimeout: const Duration(seconds: 1),
        overallTimeout: const Duration(seconds: 3),
      );

      final events = await result.events.toList();
      expect(events.last, isA<StreamingMessageStopEvent>());
    },
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.response});

  final http.Response response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(response.body)]),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
