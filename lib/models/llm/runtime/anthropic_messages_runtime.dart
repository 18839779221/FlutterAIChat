import 'dart:async';
import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:http/http.dart' as http;

import '../../../utils/logger.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../llm_usage_extractor.dart';
import 'anthropic_stream_event_adapter.dart';
import 'protocol_execution_runtime.dart';
import 'protocol_request_spec.dart';

typedef AnthropicStreamRequestExecutor =
    Stream<anthropic.MessageStreamEvent> Function({
      required anthropic.MessageCreateRequest request,
      required http.StreamedResponse streamedResponse,
    });

/// SDK-backed runtime for the Anthropic Messages protocol.
class AnthropicMessagesRuntime extends ProtocolExecutionRuntime {
  AnthropicMessagesRuntime({
    http.Client? httpClient,
    AnthropicStreamEventAdapter? streamEventAdapter,
    AnthropicStreamRequestExecutor? streamRequestExecutor,
  })  : _httpClient = httpClient,
        _streamEventAdapter = streamEventAdapter ?? const AnthropicStreamEventAdapter(),
        _streamRequestExecutor = streamRequestExecutor;

  final http.Client? _httpClient;
  final AnthropicStreamEventAdapter _streamEventAdapter;
  final AnthropicStreamRequestExecutor? _streamRequestExecutor;

  @override
  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    final spec = requestSpec as AnthropicMessagesRequestSpec;
    final client = _buildClient(runtimeConfig, timeout: timeout);
    try {
      final response = await client.messages.create(spec.request);
      final responseJson = response.toJson();
      final extractedUsage = LlmUsageExtractor.extract(responseJson);
      Logger.trace('AnthropicMessagesRuntime', 'responseJson.usage: ${responseJson['usage']}');
      Logger.trace('AnthropicMessagesRuntime', 'extractedUsage: inputTokens=${extractedUsage?.inputTokens}, '
          'cacheRead=${extractedUsage?.cacheReadInputTokens}, '
          'cacheWrite=${extractedUsage?.cacheWriteInputTokens}');
      return ProtocolExecutionResult(
        rawResponseJson: responseJson,
        cacheUsage: extractedUsage,
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
    final spec = requestSpec as AnthropicMessagesRequestSpec;
    final payload = <String, dynamic>{
      ...spec.request.toJson(),
      'stream': true,
    };
    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': runtimeConfig.apiKey,
      'anthropic-version': '2023-06-01',
    };
    final streamedResponse = await (_httpClient ?? http.Client())
        .send(
          http.Request(
            'POST',
            ApiProtocolResolver().buildRequestUri(
              runtimeConfig.apiUrl,
              ApiStyle.anthropicMessages,
            ),
          )
            ..headers.addAll(headers)
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
      final fallbackUsage = decoded is Map<String, dynamic>
          ? LlmUsageExtractor.extract(decoded)
          : null;
      return ProtocolStreamExecutionResult(
        chunks: const Stream.empty(),
        nonStreamingFallbackJson:
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
        cacheUsage: fallbackUsage,
      );
    }

    final eventStream =
        (_streamRequestExecutor ?? _createSdkStream)(
          request: spec.request,
          streamedResponse: streamedResponse,
        ).timeout(idleTimeout);

    return ProtocolStreamExecutionResult(
      chunks: _streamEventAdapter.adapt(eventStream),
    );
  }

  Stream<anthropic.MessageStreamEvent> _createSdkStream({
    required anthropic.MessageCreateRequest request,
    required http.StreamedResponse streamedResponse,
  }) async* {
    final parser = anthropic.SseParser();
    var fallbackIndex = 0;
    await for (final rawEvent in parser.parse(streamedResponse.stream)) {
      yield anthropic.MessageStreamEvent.fromJson(
        _normalizeStreamingEventJson(
          rawEvent,
          fallbackIndex: fallbackIndex,
        ),
      );
      final eventIndex = rawEvent['index'];
      if (eventIndex is int) {
        fallbackIndex = eventIndex;
      }
    }
  }

  Map<String, dynamic> _normalizeStreamingEventJson(
    Map<String, dynamic> rawEvent, {
    required int fallbackIndex,
  }) {
    final normalized = Map<String, dynamic>.from(rawEvent)..remove('_event');
    final type = normalized['type'];
    if (type == 'content_block_start' ||
        type == 'content_block_delta' ||
        type == 'content_block_stop') {
      normalized['index'] = normalized['index'] is int
          ? normalized['index']
          : fallbackIndex;
    }
    if (type == 'content_block_start') {
      final contentBlock = normalized['content_block'];
      if (contentBlock is Map) {
        final normalizedBlock = Map<String, dynamic>.from(contentBlock);
        if (normalizedBlock['type'] == 'tool_use' &&
            normalizedBlock['input'] == null) {
          normalizedBlock['input'] = const <String, dynamic>{};
        }
        if (normalizedBlock['type'] == 'thinking' &&
            normalizedBlock['signature'] == null) {
          normalizedBlock['signature'] = '';
        }
        normalized['content_block'] = normalizedBlock;
      }
    }
    return normalized;
  }

  anthropic.AnthropicClient _buildClient(
    LLMConfig runtimeConfig, {
    required Duration timeout,
  }) {
    return anthropic.AnthropicClient(
      config: anthropic.AnthropicConfig(
        authProvider: anthropic.ApiKeyProvider(runtimeConfig.apiKey),
        baseUrl: _normalizeBaseUrl(runtimeConfig.apiUrl),
        timeout: timeout,
      ),
      httpClient: _httpClient,
    );
  }

  String _normalizeBaseUrl(String apiUrl) {
    final uri = Uri.parse(apiUrl.trim());
    if (uri.path.endsWith('/v1/messages')) {
      final basePath = uri.path.substring(
        0,
        uri.path.length - '/v1/messages'.length,
      );
      return uri
          .replace(path: basePath, query: null, fragment: null)
          .toString()
          .replaceFirst(RegExp(r'/$'), '');
    }
    return apiUrl.trim().replaceFirst(RegExp(r'/$'), '');
  }
}
