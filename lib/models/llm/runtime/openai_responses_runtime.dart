import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as oai;

import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../streaming_planner_chunk.dart';
import 'responses_stream_event_adapter.dart';
import 'protocol_execution_runtime.dart';
import 'protocol_request_spec.dart';
import 'stream_tool_call_tracker.dart';

typedef OpenAiResponsesStreamRequestExecutor =
    Stream<oai.ResponseStreamEvent> Function({
      required oai.CreateResponseRequest request,
      required http.StreamedResponse streamedResponse,
    });

/// SDK-backed runtime for the OpenAI Responses protocol.
class OpenAiResponsesRuntime extends ProtocolExecutionRuntime {
  OpenAiResponsesRuntime({
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
    ResponsesStreamEventAdapter? streamEventAdapter,
    OpenAiResponsesStreamRequestExecutor? streamRequestExecutor,
  })  : _httpClient = httpClient,
        _streamClientFactory = streamClientFactory,
        _streamEventAdapter =
            streamEventAdapter ?? const ResponsesStreamEventAdapter(),
        _streamRequestExecutor = streamRequestExecutor;

  final http.Client? _httpClient;
  final http.Client Function()? _streamClientFactory;
  final ResponsesStreamEventAdapter _streamEventAdapter;
  final OpenAiResponsesStreamRequestExecutor? _streamRequestExecutor;

  @override
  Future<ProtocolExecutionResult> execute({
    required ProtocolRequestSpec requestSpec,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    final spec = requestSpec as ResponsesRequestSpec;
    final client = _buildClient(runtimeConfig, timeout: timeout);
    try {
      try {
        final response = await client.responses.create(spec.request);
        return ProtocolExecutionResult(rawResponseJson: response.toJson());
      } catch (_) {
        final fallback = await _executeFallbackJson(
          request: spec.request,
          runtimeConfig: runtimeConfig,
          timeout: timeout,
        );
        return ProtocolExecutionResult(rawResponseJson: fallback);
      }
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
    final spec = requestSpec as ResponsesRequestSpec;
    final streamedResponse = await (_httpClient ?? http.Client())
        .send(
          http.Request(
            'POST',
            ApiProtocolResolver().buildRequestUri(
              runtimeConfig.apiUrl,
              ApiStyle.responses,
            ),
          )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${runtimeConfig.apiKey}',
            })
            ..body = jsonEncode(spec.request.copyWith(stream: true).toJson()),
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
        nonStreamingFallbackJson: decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{},
      );
    }

    return ProtocolStreamExecutionResult(
      chunks: _streamRequestExecutor == null
          ? _createAdaptedChunkStream(
              streamedResponse: streamedResponse,
            ).timeout(idleTimeout)
          : _streamEventAdapter.adapt(
              _streamRequestExecutor!(
                request: spec.request,
                streamedResponse: streamedResponse,
              ).timeout(idleTimeout),
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

  Future<Map<String, dynamic>> _executeFallbackJson({
    required oai.CreateResponseRequest request,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    final response = await (_httpClient ?? http.Client())
        .post(
          Uri.parse('${runtimeConfig.apiUrl.replaceFirst(RegExp(r'/+$'), '')}/responses'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${runtimeConfig.apiKey}',
          },
          body: jsonEncode(request.toJson()),
        )
        .timeout(timeout);
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map,
    );
  }

  Stream<StreamingPlannerChunk> _createAdaptedChunkStream({
    required http.StreamedResponse streamedResponse,
  }) async* {
    final parser = oai.SseParser();
    final emittedReasoningChunks = <String>{};
    final toolCallTracker = StreamToolCallTracker();
    var fallbackOutputIndex = 0;
    final latestToolArgumentsByOutputIndex = <int, String>{};

    await for (final rawEvent in parser.parse(streamedResponse.stream)) {
      final responseId = _extractResponseId(rawEvent);
      if (responseId != null) {
        yield StreamingPlannerChunk.keepalive(
          providerMetadata: <String, dynamic>{'response_id': responseId},
        );
      }

      final typedEvent = oai.ResponseStreamEvent.fromJson(
        _normalizeStreamingEventJson(
          rawEvent,
          fallbackOutputIndex: fallbackOutputIndex,
          latestToolArgumentsByOutputIndex: latestToolArgumentsByOutputIndex,
        ),
      );
      yield* _streamEventAdapter.adaptEvent(
        typedEvent,
        emittedReasoningChunks: emittedReasoningChunks,
        toolCallTracker: toolCallTracker,
      );

      final rawOutputIndex = rawEvent['output_index'];
      if (rawOutputIndex is int) {
        fallbackOutputIndex = rawOutputIndex;
      }
      final deltaType = rawEvent['type'];
      if (deltaType == 'response.function_call_arguments.delta') {
        final normalizedIndex =
            rawOutputIndex is int ? rawOutputIndex : fallbackOutputIndex;
        final delta = rawEvent['delta'];
        if (delta is String && delta.isNotEmpty) {
          latestToolArgumentsByOutputIndex.update(
            normalizedIndex,
            (existing) => existing + delta,
            ifAbsent: () => delta,
          );
        }
      }
    }

    yield const StreamingPlannerChunk.streamCompleted();
  }

  Map<String, dynamic> _normalizeStreamingEventJson(
    Map<String, dynamic> rawEvent, {
    required int fallbackOutputIndex,
    required Map<int, String> latestToolArgumentsByOutputIndex,
  }) {
    final normalized = Map<String, dynamic>.from(rawEvent)..remove('_event');
    final type = normalized['type'];

    if (_requiresOutputIndex(type)) {
      normalized['output_index'] = normalized['output_index'] is int
          ? normalized['output_index']
          : fallbackOutputIndex;
    }

    if (type == 'response.output_text.delta') {
      normalized['content_index'] = normalized['content_index'] is int
          ? normalized['content_index']
          : 0;
    }

    if (type == 'response.output_item.added') {
      final item = normalized['item'];
      if (item is Map<String, dynamic> && item['type'] == 'function_call') {
        final outputIndex = normalized['output_index'] as int? ?? fallbackOutputIndex;
        normalized['item'] = <String, dynamic>{
          'id': item['id'] ?? 'fc_$outputIndex',
          'call_id': item['call_id'] ?? item['id'] ?? 'fc_$outputIndex',
          'name': item['name'] ?? '',
          'arguments': item['arguments'] ?? '',
          ...item,
        };
      }
    }

    if (type == 'response.function_call_arguments.done') {
      final outputIndex = normalized['output_index'] as int? ?? fallbackOutputIndex;
      normalized['arguments'] = normalized['arguments'] ??
          latestToolArgumentsByOutputIndex[outputIndex] ??
          '';
    }

    return normalized;
  }

  bool _requiresOutputIndex(dynamic type) {
    return type == 'response.output_item.added' ||
        type == 'response.output_item.done' ||
        type == 'response.output_text.delta' ||
        type == 'response.output_text.done' ||
        type == 'response.function_call_arguments.delta' ||
        type == 'response.function_call_arguments.done';
  }

  String? _extractResponseId(Map<String, dynamic> rawEvent) {
    final response = rawEvent['response'];
    if (response is Map<String, dynamic>) {
      final id = response['id'];
      if (id is String && id.trim().isNotEmpty) {
        return id;
      }
    }
    final responseId = rawEvent['response_id'];
    if (responseId is String && responseId.trim().isNotEmpty) {
      return responseId;
    }
    return null;
  }
}
