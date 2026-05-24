import 'dart:convert';

import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/runtime/anthropic_messages_runtime.dart';
import 'package:ai_chat/models/llm/runtime/protocol_request_spec.dart';
import 'package:ai_chat/models/llm/streaming_planner_chunk.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('executes anthropic json request through dedicated runtime', () async {
    final runtime = AnthropicMessagesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'id': 'msg_1',
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'model': 'claude-sonnet-4-6',
            'stop_reason': 'end_turn',
            'usage': {
              'input_tokens': 12,
              'output_tokens': 3,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await runtime.execute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {
          'model': 'claude-sonnet-4-6',
          'max_tokens': 256,
          'messages': [],
        },
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://anthropic.example/v1/messages',
        model: 'claude-sonnet-4-6',
      ),
      timeout: const Duration(seconds: 1),
    );

    expect(result.rawResponseJson['id'], 'msg_1');
  });

  test(
      'preserves provider-specific base path when anthropic endpoint includes a compatibility prefix',
      () async {
    final runtime = AnthropicMessagesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'id': 'msg_prefixed',
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'model': 'deepseek-chat',
            'stop_reason': 'end_turn',
            'usage': {
              'input_tokens': 8,
              'output_tokens': 2,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await runtime.execute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {
          'model': 'deepseek-chat',
          'max_tokens': 128,
          'messages': [],
        },
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://api.deepseek.com/anthropic/v1/messages',
        model: 'deepseek-chat',
      ),
      timeout: const Duration(seconds: 1),
    );

    expect(result.rawResponseJson['id'], 'msg_prefixed');
  });

  test('streams anthropic planner chunks through dedicated runtime', () async {
    final capturedRequests = <anthropic.MessageCreateRequest>[];
    final runtime = AnthropicMessagesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          'not sdk stream content',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
      streamRequestExecutor: ({required request, required streamedResponse}) {
        capturedRequests.add(request);
        return Stream<anthropic.MessageStreamEvent>.fromIterable(const [
          anthropic.ContentBlockStartEvent(
            index: 0,
            contentBlock: anthropic.ToolUseBlock(
              id: 'toolu_1',
              name: 'write_file',
              input: {'path': 'a.txt'},
            ),
          ),
          anthropic.ContentBlockDeltaEvent(
            index: 0,
            delta: anthropic.InputJsonDelta('{"path":"a.txt"}'),
          ),
          anthropic.ContentBlockStopEvent(index: 0),
          anthropic.MessageStopEvent(),
        ]);
      },
    );

    final result = await runtime.streamExecute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {
          'model': 'claude-sonnet-4-6',
          'max_tokens': 256,
          'messages': [],
        },
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://anthropic.example/v1/messages',
        model: 'claude-sonnet-4-6',
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
            chunk.providerCallId == 'toolu_1' &&
            chunk.toolName == 'write_file',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallArgumentsDelta &&
            chunk.toolCallIndex == 0 &&
            chunk.providerCallId == 'toolu_1' &&
            chunk.argumentsTextDelta == '{"path":"a.txt"}',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallCompleted &&
            chunk.toolCallIndex == 0,
      ),
      isTrue,
    );
  });

  test('falls back to non-stream json when response is not text/event-stream',
      () async {
    var streamExecutorCalled = false;
    final runtime = AnthropicMessagesRuntime(
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'id': 'msg_fallback',
            'type': 'message',
            'content': [
              {'type': 'text', 'text': 'fallback'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      streamRequestExecutor: ({required request, required streamedResponse}) {
        streamExecutorCalled = true;
        return const Stream<anthropic.MessageStreamEvent>.empty();
      },
    );

    final result = await runtime.streamExecute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {
          'model': 'claude-sonnet-4-6',
          'max_tokens': 256,
          'messages': [],
        },
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://anthropic.example/v1/messages',
        model: 'claude-sonnet-4-6',
      ),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 3),
    );

    expect(await result.chunks.toList(), isEmpty);
    expect(streamExecutorCalled, isFalse);
    expect(result.nonStreamingFallbackJson?['id'], 'msg_fallback');
  });

  test(
      'normalizes anthropic stream events before sdk parsing when tool input or index is missing',
      () async {
    final runtime = AnthropicMessagesRuntime(
      httpClient: _FakeHttpClient(
        streamedResponse: http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"先分析"}}\n\n'
              'event: content_block_start\n'
              'data: {"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_2","name":"write_file"}}\n\n'
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\\"path\\":\\"b.txt\\"}"}}\n\n'
              'event: content_block_stop\n'
              'data: {"type":"content_block_stop"}\n\n'
              'event: message_stop\n'
              'data: {"type":"message_stop"}\n\n'
              'data: [DONE]\n',
            ),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
    );

    final result = await runtime.streamExecute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {
          'model': 'claude-sonnet-4-6',
          'max_tokens': 256,
          'messages': [],
        },
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://anthropic.example/v1/messages',
        model: 'claude-sonnet-4-6',
      ),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 3),
    );

    final chunks = await result.chunks.toList();

    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.reasoningDelta &&
            chunk.content == '先分析',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallStarted &&
            chunk.toolCallIndex == 0 &&
            chunk.providerCallId == 'toolu_2' &&
            chunk.toolName == 'write_file',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallArgumentsDelta &&
            chunk.toolCallIndex == 0 &&
            chunk.argumentsTextDelta == '{"path":"b.txt"}',
      ),
      isTrue,
    );
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.toolCallCompleted &&
            chunk.toolCallIndex == 0,
      ),
      isTrue,
    );
  });

  test(
      'normalizes thinking content_block_start without signature before sdk parsing',
      () async {
    final runtime = AnthropicMessagesRuntime(
      httpClient: _FakeHttpClient(
        streamedResponse: http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'event: content_block_start\n'
              'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"先分析"}}\n\n'
              'event: content_block_delta\n'
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"，再继续"}}\n\n'
              'event: content_block_stop\n'
              'data: {"type":"content_block_stop","index":0}\n\n'
              'event: message_stop\n'
              'data: {"type":"message_stop"}\n\n'
              'data: [DONE]\n',
            ),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
    );

    final result = await runtime.streamExecute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {
          'model': 'claude-sonnet-4-6',
          'max_tokens': 256,
          'messages': [],
        },
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://anthropic.example/v1/messages',
        model: 'claude-sonnet-4-6',
      ),
      idleTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(seconds: 3),
    );

    final chunks = await result.chunks.toList();
    expect(
      chunks.any(
        (chunk) =>
            chunk.type == StreamingPlannerChunkType.reasoningDelta &&
            chunk.content == '，再继续',
      ),
      isTrue,
    );
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({this.response, this.streamedResponse});

  final http.Response? response;
  final http.StreamedResponse? streamedResponse;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (streamedResponse != null) {
      return streamedResponse!;
    }
    final response = this.response!;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(response.body)]),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
