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
import 'chat_completions_stream_event_adapter.dart';
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
  static const ChatCompletionsStreamEventAdapter _streamEventAdapter =
      ChatCompletionsStreamEventAdapter();

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
      final responseJson = response.toJson();
      final extractedUsage = LlmUsageExtractor.extract(responseJson);
      Logger.trace('OpenAiChatCompletionsRuntime', 'responseJson.usage: ${responseJson['usage']}');
      Logger.trace('OpenAiChatCompletionsRuntime', 'extractedUsage: inputTokens=${extractedUsage?.inputTokens}, '
          'cachedInputTokens=${extractedUsage?.cachedInputTokens}');
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
        return ProtocolStreamExecutionResult(
          events: const Stream.empty(),
          nonStreamingFallbackJson: <String, dynamic>{},
        );
      }
      final decoded = jsonDecode(responseText);
      final fallbackUsage = decoded is Map<String, dynamic>
          ? LlmUsageExtractor.extract(decoded)
          : null;
      return ProtocolStreamExecutionResult(
        events: const Stream.empty(),
        nonStreamingFallbackJson:
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
        cacheUsage: fallbackUsage,
      );
    }

    LlmCacheUsage? collectedUsage;
    return ProtocolStreamExecutionResult(
      events: _createAdaptedEventStream(
        streamedResponse: streamedResponse,
        onUsageExtracted: (usage) => collectedUsage = usage,
      ).timeout(idleTimeout),
      cacheUsage: collectedUsage,
    );
  }

  Stream<StreamingMessageEvent> _createAdaptedEventStream({
    required http.StreamedResponse streamedResponse,
    void Function(LlmCacheUsage?)? onUsageExtracted,
  }) async* {
    final normalizedChunks = <Map<String, dynamic>>[];
    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }

      if (line.contains('[DONE]')) {
        Logger.i('OpenAiChatCompletionsRuntime', 'Chat Completions planner 流式响应完成');
        continue;
      }

      try {
        final data = jsonDecode(line.substring(6));
        if (data is! Map<String, dynamic>) {
          continue;
        }

        // Extract usage from the chunk if present
        final usage = data['usage'];
        if (usage is Map<String, dynamic>) {
          final extractedUsage = LlmUsageExtractor.extract(data);
          if (extractedUsage != null && onUsageExtracted != null) {
            onUsageExtracted(extractedUsage);
            Logger.trace('OpenAiChatCompletionsRuntime', 'stream usage extracted: inputTokens=${extractedUsage.inputTokens}, '
                'cachedInputTokens=${extractedUsage.cachedInputTokens}');
          }
        }

        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) {
          continue;
        }
        final firstChoice = choices.first;
        if (firstChoice is! Map) {
          continue;
        }
        final delta = firstChoice['delta'];
        if (delta is! Map) {
          continue;
        }

        normalizedChunks.add(data);
      } catch (e) {
        Logger.e('OpenAiChatCompletionsRuntime', 'Chat Completions planner JSON解析错误: $e');
      }
    }
    yield* _streamEventAdapter.adapt(
      Stream<Map<String, dynamic>>.fromIterable(normalizedChunks),
    );
    if (normalizedChunks.isNotEmpty) {
      final lastChunk = normalizedChunks.last;
      final messageId = _normalizeText(lastChunk['id']);
      if (messageId != null) {
        yield StreamingMessageStopEvent(
          messageId: messageId,
          providerMetadata: _providerStateFromChatCompletions(lastChunk),
        );
      }
    }
  }

  Map<String, dynamic>? _providerStateFromChatCompletions(
    Map<String, dynamic> data,
  ) {
    final responseId = _normalizeText(data['id']);
    if (responseId == null) {
      return null;
    }
    return {'response_id': responseId};
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) {
      return null;
    }
    return value.isEmpty ? null : value;
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
