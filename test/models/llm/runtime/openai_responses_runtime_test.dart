import 'dart:convert';

import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/runtime/openai_responses_runtime.dart';
import 'package:ai_chat/models/llm/runtime/protocol_request_spec.dart';
import 'package:ai_chat/models/llm/streaming_planner_chunk.dart';
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

  test('streams responses planner chunks through typed event adapter', () async {
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

    final chunks = await result.chunks.toList();

    expect(capturedRequests, hasLength(1));
    expect(capturedRequests.single.toJson()['stream'], isNot(true));
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallStarted &&
            chunk.toolCallIndex == 0 &&
            chunk.providerCallId == 'call_1' &&
            chunk.toolName == 'web_search',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallArgumentsDelta &&
            chunk.argumentsTextDelta == '{"query":"flutter"}',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallCompleted &&
            chunk.providerCallId == 'call_1',
      ),
      isTrue,
    );
    expect(chunks.last.type, StreamingPlannerChunkType.streamCompleted);
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

    expect(await result.chunks.toList(), isEmpty);
    expect(streamExecutorCalled, isFalse);
    expect(result.nonStreamingFallbackJson?['id'], 'resp_fallback');
  });
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
