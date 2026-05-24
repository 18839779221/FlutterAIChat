import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_protocol_resolver.dart';
import '../api_stream_parser.dart';
import '../llm_config.dart';
import 'protocol_execution_runtime.dart';
import 'protocol_request_spec.dart';

/// Raw JSON HTTP runtime used by protocols not yet migrated to a dedicated SDK.
class HttpJsonProtocolRuntime extends ProtocolExecutionRuntime {
  HttpJsonProtocolRuntime({
    required ApiStyle apiStyle,
    required http.Client httpClient,
    ApiStreamParser? streamParser,
  })  : _apiStyle = apiStyle,
        _httpClient = httpClient,
        _streamParser = streamParser ?? const ApiStreamParser();

  final ApiStyle _apiStyle;
  final http.Client _httpClient;
  final ApiStreamParser _streamParser;

  @override
  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    final spec = requestSpec as JsonProtocolRequestSpec;
    final response = await _httpClient
        .post(
          ApiProtocolResolver().buildRequestUri(runtimeConfig.apiUrl, _apiStyle),
          headers: spec.headers,
          body: jsonEncode(spec.payload),
        )
        .timeout(timeout);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return ProtocolExecutionResult(
      rawResponseJson: Map<String, dynamic>.from(decoded as Map),
    );
  }

  @override
  Future<ProtocolStreamExecutionResult> streamExecute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration idleTimeout,
    required Duration overallTimeout,
  }) async {
    final spec = requestSpec as JsonProtocolRequestSpec;
    final streamingPayload = <String, dynamic>{
      ...spec.payload,
      'stream': true,
    };
    final streamedResponse = await _httpClient
        .send(
          http.Request(
            'POST',
            ApiProtocolResolver().buildRequestUri(runtimeConfig.apiUrl, _apiStyle),
          )
            ..headers.addAll(spec.headers)
            ..body = jsonEncode(streamingPayload),
        )
        .timeout(idleTimeout);

    final contentType = streamedResponse.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final responseText =
          await streamedResponse.stream.bytesToString().timeout(idleTimeout);
      final decoded = jsonDecode(responseText);
      return ProtocolStreamExecutionResult(
        chunks: const Stream.empty(),
        nonStreamingFallbackJson: decoded is Map<String, dynamic>
            ? decoded
            : Map<String, dynamic>.from(decoded as Map),
      );
    }

    return ProtocolStreamExecutionResult(
      chunks: _streamParser.parsePlannerChunks(streamedResponse, _apiStyle),
    );
  }
}
