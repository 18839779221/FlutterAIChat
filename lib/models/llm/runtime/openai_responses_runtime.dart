import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as oai;

import '../../../utils/logger.dart';
import '../api_protocol_resolver.dart';
import '../llm_cache_usage.dart';
import '../llm_config.dart';
import '../llm_usage_extractor.dart';
import '../streaming_message_event.dart';
import 'responses_stream_event_adapter.dart';
import 'protocol_execution_runtime.dart';
import 'protocol_request_spec.dart';

typedef OpenAiResponsesStreamRequestExecutor =
    Stream<oai.ResponseStreamEvent> Function({
      required oai.CreateResponseRequest request,
      required http.StreamedResponse streamedResponse,
    });

/// SDK-backed runtime for the OpenAI Responses protocol.
class OpenAiResponsesRuntime extends ProtocolExecutionRuntime {
  static const int _streamEventPreviewMaxChars = 4000;

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
        final responseJson = response.toJson();
        final extractedUsage = LlmUsageExtractor.extract(responseJson);
        Logger.trace('OpenAiResponsesRuntime', 'responseJson.usage: ${responseJson['usage']}');
        Logger.trace('OpenAiResponsesRuntime', 'extractedUsage: inputTokens=${extractedUsage?.inputTokens}, '
            'cachedInputTokens=${extractedUsage?.cachedInputTokens}');
        return ProtocolExecutionResult(
          rawResponseJson: responseJson,
          cacheUsage: extractedUsage,
        );
      } catch (error, stackTrace) {
        Logger.w(
          'OpenAiResponsesRuntime',
          'responses sdk execution failed, falling back to raw http: $error',
        );
        Logger.trace(
          'OpenAiResponsesRuntime',
          'responses sdk failure stack: $stackTrace',
        );
        final fallback = await _executeFallbackJson(
          payload: spec.request.toJson(),
          runtimeConfig: runtimeConfig,
          timeout: timeout,
        );
        final extractedUsage = LlmUsageExtractor.extract(fallback);
        Logger.trace('OpenAiResponsesRuntime', 'fallback.usage: ${fallback['usage']}');
        Logger.trace('OpenAiResponsesRuntime', 'fallback extractedUsage: inputTokens=${extractedUsage?.inputTokens}, '
            'cachedInputTokens=${extractedUsage?.cachedInputTokens}');
        return ProtocolExecutionResult(
          rawResponseJson: fallback,
          cacheUsage: extractedUsage,
        );
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
    final payload = spec.request.toJson();
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
            ..body = jsonEncode({
              ...payload,
              'stream': true,
            }),
        )
        .timeout(idleTimeout);

    final contentType = streamedResponse.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final responseText =
          await streamedResponse.stream.bytesToString().timeout(idleTimeout);
      final statusCode = streamedResponse.statusCode;
      final reasonPhrase = streamedResponse.reasonPhrase;
      if (responseText.trim().isEmpty) {
        Logger.w(
          'OpenAiResponsesRuntime',
          'responses stream returned non-SSE empty body '
          'status=$statusCode reason=${reasonPhrase ?? ''}',
        );
        return ProtocolStreamExecutionResult(
          events: const Stream.empty(),
          nonStreamingFallbackJson: <String, dynamic>{
            '_http_status': statusCode,
            if (reasonPhrase != null && reasonPhrase.isNotEmpty)
              '_http_reason': reasonPhrase,
          },
        );
      }
      final decoded = jsonDecode(responseText);
      if (statusCode < 200 || statusCode >= 300) {
        Logger.w(
          'OpenAiResponsesRuntime',
          'responses stream returned non-SSE error '
          'status=$statusCode reason=${reasonPhrase ?? ''} body=$responseText',
        );
      }
      final fallbackUsage = decoded is Map<String, dynamic>
          ? LlmUsageExtractor.extract(decoded)
          : null;
      return ProtocolStreamExecutionResult(
        events: const Stream.empty(),
        nonStreamingFallbackJson: decoded is Map<String, dynamic>
            ? <String, dynamic>{
                ...decoded,
                '_http_status': statusCode,
                if (reasonPhrase != null && reasonPhrase.isNotEmpty)
                  '_http_reason': reasonPhrase,
              }
            : <String, dynamic>{
                '_http_status': statusCode,
                if (reasonPhrase != null && reasonPhrase.isNotEmpty)
                  '_http_reason': reasonPhrase,
              },
        cacheUsage: fallbackUsage,
      );
    }

    LlmCacheUsage? collectedUsage;
    return ProtocolStreamExecutionResult(
      events: _streamRequestExecutor == null
          ? _createAdaptedEventStream(
              streamedResponse: streamedResponse,
              onUsageExtracted: (usage) => collectedUsage = usage,
            ).timeout(idleTimeout)
          : _streamEventAdapter.adaptPreview(
              _streamRequestExecutor!(
                request: spec.request,
                streamedResponse: streamedResponse,
              ).timeout(idleTimeout),
            ),
      cacheUsage: collectedUsage,
    );
  }

  oai.OpenAIClient _buildClient(
    LLMConfig runtimeConfig, {
    required Duration timeout,
  }) {
    return oai.OpenAIClient(
      config: oai.OpenAIConfig(
        authProvider: oai.ApiKeyProvider(runtimeConfig.apiKey),
        baseUrl: _normalizeBaseUrl(runtimeConfig.apiUrl),
        timeout: timeout,
      ),
      httpClient: _httpClient,
      streamClientFactory: _streamClientFactory,
    );
  }

  String _normalizeBaseUrl(String apiUrl) {
    final uri = Uri.parse(apiUrl.trim());
    if (uri.path.endsWith('/responses')) {
      final basePath = uri.path.substring(
        0,
        uri.path.length - '/responses'.length,
      );
      return uri
          .replace(path: basePath, query: null, fragment: null)
          .toString()
          .replaceFirst(RegExp(r'/$'), '');
    }
    return apiUrl.trim().replaceFirst(RegExp(r'/$'), '');
  }

  Future<Map<String, dynamic>> _executeFallbackJson({
    required Map<String, dynamic> payload,
    required LLMConfig runtimeConfig,
    required Duration timeout,
  }) async {
    final response = await (_httpClient ?? http.Client())
        .post(
          const ApiProtocolResolver().buildRequestUri(
            runtimeConfig.apiUrl,
            ApiStyle.responses,
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${runtimeConfig.apiKey}',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map,
    );
  }

  Stream<StreamingMessageEvent> _createAdaptedEventStream({
    required http.StreamedResponse streamedResponse,
    void Function(LlmCacheUsage?)? onUsageExtracted,
  }) async* {
    const parser = oai.SseParser();
    var fallbackOutputIndex = 0;
    final latestToolArgumentsByOutputIndex = <int, String>{};
    final normalizedEvents = <oai.ResponseStreamEvent>[];
    String? responseId;

    await for (final rawEvent in parser.parse(streamedResponse.stream)) {
      responseId ??= _extractResponseId(rawEvent);
      Logger.temp(
        'OpenAiResponsesRuntime',
        'responses.stream.raw_event',
        reason: 'diagnose_provider_stream_shape_before_sdk_parse',
        data: {
          'eventType': rawEvent['type'] ?? 'unknown',
          'rawEventPreview': _previewJson(rawEvent),
        },
      );
      // Extract usage from response.done event
      if (rawEvent['type'] == 'response.done') {
        final response = rawEvent['response'];
        if (response is Map<String, dynamic>) {
          final usage = LlmUsageExtractor.extract(response);
          if (usage != null && onUsageExtracted != null) {
            onUsageExtracted(usage);
            Logger.trace('OpenAiResponsesRuntime', 'stream usage extracted: inputTokens=${usage.inputTokens}, '
                'cachedInputTokens=${usage.cachedInputTokens}');
          }
        }
      }

      final normalizedJson = _normalizeStreamingEventJson(
        rawEvent,
        fallbackOutputIndex: fallbackOutputIndex,
        latestToolArgumentsByOutputIndex: latestToolArgumentsByOutputIndex,
      );
      if (responseId != null &&
          normalizedJson['response_id'] == null &&
          normalizedJson['response'] == null) {
        normalizedJson['response_id'] = responseId;
      }
      Logger.temp(
        'OpenAiResponsesRuntime',
        'responses.stream.normalized_event',
        reason: 'diagnose_provider_stream_shape_before_sdk_parse',
        data: {
          'eventType': normalizedJson['type'] ?? rawEvent['type'] ?? 'unknown',
          'normalizedEventPreview': _previewJson(normalizedJson),
        },
      );
      try {
        final typedEvent = oai.ResponseStreamEvent.fromJson(normalizedJson);
        normalizedEvents.add(typedEvent);
      } catch (error) {
        final type = rawEvent['type'];
        Logger.e(
          'OpenAiResponsesRuntime',
          'responses.stream.typed_event_parse_failed '
          'type=${type ?? 'unknown'} '
          'rawEvent=${_previewJson(rawEvent)} '
          'normalizedEvent=${_previewJson(normalizedJson)}',
          error,
        );
        if (_canSkipTypedEventParseFailure(type, normalizedJson)) {
          Logger.w(
            'OpenAiResponsesRuntime',
            'skip provider-incompatible responses stream event '
            'type=${type ?? 'unknown'} error=$error',
          );
        } else {
          rethrow;
        }
      }

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

    if (responseId != null) {
      yield StreamingMessageStartEvent(
        messageId: responseId,
        providerMetadata: {'response_id': responseId},
      );
    }
    yield* _streamEventAdapter.adaptPreview(
      Stream<oai.ResponseStreamEvent>.fromIterable(normalizedEvents),
    );
  }

  bool _canSkipTypedEventParseFailure(
    dynamic type,
    Map<String, dynamic> normalizedJson,
  ) {
    if (type != 'response.completed' && type != 'response.done') {
      return false;
    }
    final response = normalizedJson['response'];
    if (response is! Map<String, dynamic>) {
      return false;
    }
    return response['output'] == null;
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

  String _previewJson(Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    if (encoded.length <= _streamEventPreviewMaxChars) {
      return encoded;
    }
    return '${encoded.substring(0, _streamEventPreviewMaxChars - 3)}...';
  }

}
