import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as oai;

import '../api_protocol_resolver.dart';
import '../api_stream_parser.dart';
import '../llm_config.dart';
import 'protocol_execution_runtime.dart';
import 'protocol_request_spec.dart';

/// SDK-backed runtime for the Chat Completions protocol.
class OpenAiChatCompletionsRuntime extends ProtocolExecutionRuntime {
  OpenAiChatCompletionsRuntime({
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  })  : _httpClient = httpClient,
        _streamClientFactory = streamClientFactory;

  final http.Client? _httpClient;
  final http.Client Function()? _streamClientFactory;
  static const ApiStreamParser _streamParser = ApiStreamParser();

  @override
  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    final spec = requestSpec as ChatCompletionsRequestSpec;
    final client = _buildClient(runtimeConfig, timeout: timeout);
    try {
      final response = await client.chat.completions.create(spec.request);
      return ProtocolExecutionResult(
        rawResponseJson: response.toJson(),
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<ProtocolStreamExecutionResult> streamExecute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration idleTimeout,
    required Duration overallTimeout,
  }) async {
    final spec = requestSpec as ChatCompletionsRequestSpec;
    final payload = <String, dynamic>{
      ...spec.request.toJson(),
      'stream': true,
    };
    final streamedResponse = await (_httpClient ?? http.Client())
        .send(
          http.Request(
            'POST',
            ApiProtocolResolver().buildRequestUri(
              runtimeConfig.apiUrl,
              ApiStyle.chatCompletions,
            ),
          )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${runtimeConfig.apiKey}',
            })
            ..body = jsonEncode(payload),
        )
        .timeout(idleTimeout);

    final contentType = streamedResponse.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final responseText =
          await streamedResponse.stream.bytesToString().timeout(idleTimeout);
      if (responseText.trim().isEmpty) {
        return const ProtocolStreamExecutionResult(
          chunks: Stream.empty(),
          nonStreamingFallbackJson: <String, dynamic>{},
        );
      }
      final decoded = jsonDecode(responseText);
      return ProtocolStreamExecutionResult(
        chunks: const Stream.empty(),
        nonStreamingFallbackJson:
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
      );
    }

    return ProtocolStreamExecutionResult(
      chunks: _streamParser.parsePlannerChunks(
        streamedResponse,
        ApiStyle.chatCompletions,
      ),
    );
  }

  oai.OpenAIClient _buildClient(
    LLMConfig runtimeConfig, {
    required Duration timeout,
  }) {
    return oai.OpenAIClient(
      config: oai.OpenAIConfig(
        authProvider: oai.ApiKeyProvider(runtimeConfig.apiKey),
        baseUrl: runtimeConfig.apiUrl,
        timeout: timeout,
      ),
      httpClient: _httpClient,
      streamClientFactory: _streamClientFactory,
    );
  }
}
