import 'dart:async';
import 'dart:convert';

import 'package:openai_dart/openai_dart.dart' as oai;
import 'package:http/http.dart' as http;

import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../streaming_message_event.dart';
import 'chat_completions_stream_event_adapter.dart';
import 'responses_stream_event_adapter.dart';
import 'protocol_execution_runtime.dart';
import 'protocol_request_spec.dart';

/// Raw JSON HTTP runtime used by protocols not yet migrated to a dedicated SDK.
class HttpJsonProtocolRuntime extends ProtocolExecutionRuntime {
  HttpJsonProtocolRuntime({
    required ApiStyle apiStyle,
    required http.Client httpClient,
  })  : _apiStyle = apiStyle,
        _httpClient = httpClient;

  final ApiStyle _apiStyle;
  final http.Client _httpClient;
  static const ChatCompletionsStreamEventAdapter _chatCompletionsAdapter =
      ChatCompletionsStreamEventAdapter();
  static const ResponsesStreamEventAdapter _responsesEventAdapter =
      ResponsesStreamEventAdapter();

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
        events: const Stream.empty(),
        nonStreamingFallbackJson: decoded is Map<String, dynamic>
            ? decoded
            : Map<String, dynamic>.from(decoded as Map),
      );
    }

    return ProtocolStreamExecutionResult(
      events: _eventStreamFor(streamedResponse),
    );
  }

  Stream<StreamingMessageEvent> _eventStreamFor(
    http.StreamedResponse streamedResponse,
  ) {
    switch (_apiStyle) {
      case ApiStyle.chatCompletions:
        return _createChatCompletionsEventStream(streamedResponse);
      case ApiStyle.responses:
        return _createResponsesEventStream(streamedResponse);
      case ApiStyle.anthropicMessages:
        throw UnsupportedError(
          'Anthropic planner streaming must use AnthropicMessagesRuntime '
          'with AnthropicStreamEventAdapter instead of HttpJsonProtocolRuntime.',
        );
    }
  }

  Stream<StreamingMessageEvent> _createChatCompletionsEventStream(
    http.StreamedResponse streamedResponse,
  ) async* {
    final normalizedChunks = <Map<String, dynamic>>[];
    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }
      if (line.contains('[DONE]')) {
        continue;
      }
      final decoded = jsonDecode(line.substring(6));
      if (decoded is Map<String, dynamic>) {
        normalizedChunks.add(decoded);
      }
    }
    yield* _chatCompletionsAdapter.adapt(
      Stream<Map<String, dynamic>>.fromIterable(normalizedChunks),
    );
    if (normalizedChunks.isNotEmpty) {
      final messageId = _normalizeText(normalizedChunks.last['id']);
      if (messageId != null) {
        yield StreamingMessageStopEvent(
          messageId: messageId,
          providerMetadata: {'response_id': messageId},
        );
      }
    }
  }

  Stream<StreamingMessageEvent> _createResponsesEventStream(
    http.StreamedResponse streamedResponse,
  ) async* {
    final normalizedEvents = <oai.ResponseStreamEvent>[];
    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }
      if (line.contains('[DONE]')) {
        continue;
      }
      final decoded = jsonDecode(line.substring(6));
      if (decoded is Map<String, dynamic>) {
        normalizedEvents.add(oai.ResponseStreamEvent.fromJson(decoded));
      }
    }
    yield* _responsesEventAdapter.adaptPreview(
      Stream<oai.ResponseStreamEvent>.fromIterable(normalizedEvents),
    );
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) {
      return null;
    }
    return value.isEmpty ? null : value;
  }
}
