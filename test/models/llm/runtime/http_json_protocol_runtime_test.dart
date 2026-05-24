import 'dart:convert';

import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_config.dart';
import 'package:ai_chat/models/llm/runtime/http_json_protocol_runtime.dart';
import 'package:ai_chat/models/llm/runtime/protocol_request_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('executes json protocol runtime for anthropic request specs', () async {
    final runtime = HttpJsonProtocolRuntime(
      apiStyle: ApiStyle.anthropicMessages,
      httpClient: _FakeHttpClient(
        response: http.Response(
          jsonEncode({
            'id': 'msg_1',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await runtime.execute(
      requestSpec: const JsonProtocolRequestSpec(
        payload: {'model': 'claude', 'messages': []},
        headers: {'x-api-key': 'k'},
      ),
      runtimeConfig: const LLMConfig(
        apiKey: 'k',
        apiUrl: 'https://anthropic.example/v1/messages',
        model: 'claude',
      ),
      timeout: const Duration(seconds: 1),
    );

    expect(result.rawResponseJson['id'], 'msg_1');
  });

  test(
      'rejects anthropic planner streaming on legacy json runtime path',
      () async {
    final runtime = HttpJsonProtocolRuntime(
      apiStyle: ApiStyle.anthropicMessages,
      httpClient: _FakeHttpClient(
        response: http.Response(
          'event: content_block_start\n'
          'data: {"type":"content_block_start"}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
    );

    expect(
      () => runtime.streamExecute(
        requestSpec: const JsonProtocolRequestSpec(
          payload: {'model': 'claude', 'messages': []},
          headers: {'x-api-key': 'k'},
        ),
        runtimeConfig: const LLMConfig(
          apiKey: 'k',
          apiUrl: 'https://anthropic.example/v1/messages',
          model: 'claude',
        ),
        idleTimeout: const Duration(seconds: 1),
        overallTimeout: const Duration(seconds: 3),
      ),
      throwsA(isA<UnsupportedError>()),
    );
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
