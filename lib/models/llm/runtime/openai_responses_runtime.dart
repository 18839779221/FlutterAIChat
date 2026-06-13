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
      final response = await client.responses.create(spec.request);
      final responseJson = response.toJson();
      final extractedUsage = LlmUsageExtractor.extract(responseJson);
      Logger.trace(
        'OpenAiResponsesRuntime',
        'responseJson.usage: ${responseJson['usage']}',
      );
      Logger.trace(
        'OpenAiResponsesRuntime',
        'extractedUsage: inputTokens=${extractedUsage?.inputTokens}, '
        'cachedInputTokens=${extractedUsage?.cachedInputTokens}',
      );
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
      httpClient: _SdkCompatibleResponsesHttpClient(
        inner: _httpClient ?? http.Client(),
      ),
      streamClientFactory: _streamClientFactory,
    );
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
        rethrow;
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

  Map<String, dynamic> _normalizeStreamingEventJson(
    Map<String, dynamic> rawEvent, {
    required int fallbackOutputIndex,
    required Map<int, String> latestToolArgumentsByOutputIndex,
  }) {
    final normalized = Map<String, dynamic>.from(rawEvent)..remove('_event');
    final type = normalized['type'];

    if (type == 'response.completed' ||
        type == 'response.done' ||
        type == 'response.failed') {
      final response = normalized['response'];
      if (response is Map<String, dynamic>) {
        normalized['response'] =
            _SdkCompatibleResponsesNormalizer.normalizeResponseJsonForSdk(
          response,
        );
      }
    }

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

class _SdkCompatibleResponsesHttpClient extends http.BaseClient {
  _SdkCompatibleResponsesHttpClient({required this.inner});

  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (!_shouldNormalize(request, response)) {
      return response;
    }

    final bodyBytes = await response.stream.toBytes();
    final normalizedBytes = _normalizeBodyBytes(bodyBytes);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([normalizedBytes]),
      response.statusCode,
      contentLength: normalizedBytes.length,
      request: request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    inner.close();
  }

  bool _shouldNormalize(
    http.BaseRequest request,
    http.StreamedResponse response,
  ) {
    if (request.method.toUpperCase() != 'POST') {
      return false;
    }
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      return false;
    }
    return request.url.path.endsWith('/responses');
  }

  List<int> _normalizeBodyBytes(List<int> bodyBytes) {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      return bodyBytes;
    }
    final normalized =
        _SdkCompatibleResponsesNormalizer.normalizeResponseJsonForSdk(decoded);
    return utf8.encode(jsonEncode(normalized));
  }
}

class _SdkCompatibleResponsesNormalizer {
  static Map<String, dynamic> normalizeResponseJsonForSdk(
    Map<String, dynamic> json,
  ) {
    final normalized = Map<String, dynamic>.from(json);
    normalized['object'] = normalized['object'] ?? 'response';
    normalized['created_at'] = _coerceCreatedAt(normalized['created_at']);
    normalized['status'] = _normalizeResponseStatus(normalized['status']);

    final rawOutput = normalized['output'];
    if (rawOutput is List) {
      normalized['output'] = rawOutput
          .map((item) => _normalizeOutputItem(item))
          .toList(growable: false);
    } else {
      normalized['output'] = const <Map<String, dynamic>>[];
    }
    return normalized;
  }

  static Map<String, dynamic> _normalizeOutputItem(dynamic rawItem) {
    if (rawItem is! Map) {
      return const <String, dynamic>{'type': 'unknown'};
    }
    final item = Map<String, dynamic>.from(rawItem);
    if (item['type'] == 'message') {
      item['id'] = _nonEmptyString(item['id']) ?? _syntheticMessageId(item);
      item['role'] = _nonEmptyString(item['role']) ?? 'assistant';
      item['status'] = _nonEmptyString(item['status']) ?? 'completed';
      final rawContent = item['content'];
      if (rawContent is List) {
        item['content'] = rawContent
            .map((entry) => _normalizeMessageContent(entry))
            .toList(growable: false);
      } else {
        item['content'] = const <Map<String, dynamic>>[];
      }
    }
    return item;
  }

  static Map<String, dynamic> _normalizeMessageContent(dynamic rawEntry) {
    if (rawEntry is! Map) {
      return const <String, dynamic>{
        'type': 'output_text',
        'text': '',
      };
    }
    final entry = Map<String, dynamic>.from(rawEntry);
    final type = _nonEmptyString(entry['type']) ?? 'output_text';
    entry['type'] = type;
    if ((type == 'output_text' ||
            type == 'reasoning_text' ||
            type == 'summary_text' ||
            type == 'input_text') &&
        entry['text'] is! String) {
      entry['text'] = '';
    }
    if (type == 'refusal' && entry['refusal'] is! String) {
      entry['refusal'] = '';
    }
    return entry;
  }

  static int _coerceCreatedAt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return 0;
  }

  static String _normalizeResponseStatus(dynamic value) {
    return _nonEmptyString(value) ?? 'completed';
  }

  static String? _nonEmptyString(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _syntheticMessageId(Map<String, dynamic> item) {
    final textHash = item['content'].hashCode.toUnsigned(20).toRadixString(16);
    return 'msg_$textHash';
  }
}
