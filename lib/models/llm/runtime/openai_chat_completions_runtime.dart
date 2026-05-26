import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as oai;

import '../../../utils/logger.dart';
import '../api_protocol_resolver.dart';
import '../llm_cache_usage.dart';
import '../llm_config.dart';
import '../llm_usage_extractor.dart';
import '../streaming_planner_chunk.dart';
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

    LlmCacheUsage? collectedUsage;
    return ProtocolStreamExecutionResult(
      chunks: _createAdaptedChunkStream(
        streamedResponse: streamedResponse,
        onUsageExtracted: (usage) => collectedUsage = usage,
      ).timeout(idleTimeout),
      cacheUsage: collectedUsage,
    );
  }

  Stream<StreamingPlannerChunk> _createAdaptedChunkStream({
    required http.StreamedResponse streamedResponse,
    void Function(LlmCacheUsage?)? onUsageExtracted,
  }) async* {
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
          // Emit usage as metadata in a keepalive chunk
          yield StreamingPlannerChunk.keepalive(
            providerMetadata: <String, dynamic>{
              '_usage': <String, dynamic>{
                if (extractedUsage?.inputTokens != null) 'inputTokens': extractedUsage!.inputTokens,
                if (extractedUsage?.outputTokens != null) 'outputTokens': extractedUsage!.outputTokens,
                if (extractedUsage?.cachedInputTokens != null) 'cachedInputTokens': extractedUsage!.cachedInputTokens,
                if (extractedUsage?.cacheReadInputTokens != null) 'cacheReadInputTokens': extractedUsage!.cacheReadInputTokens,
                if (extractedUsage?.cacheWriteInputTokens != null) 'cacheWriteInputTokens': extractedUsage!.cacheWriteInputTokens,
              },
            },
          );
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

        final content = _normalizeText(delta['content']);
        if (content != null) {
          yield StreamingPlannerChunk.contentDelta(
            content,
            providerMetadata: _providerStateFromChatCompletions(data),
          );
        }
        final reasoning = _normalizeText(
          delta['reasoning_content'] ?? delta['reasoning'] ?? delta['thinking'],
        );
        if (reasoning != null) {
          yield StreamingPlannerChunk.reasoningDelta(
            reasoning,
            providerMetadata: _providerStateFromChatCompletions(data),
          );
        }

        final toolCalls = delta['tool_calls'];
        if (toolCalls is! List) {
          continue;
        }
        for (var toolCallPosition = 0;
            toolCallPosition < toolCalls.length;
            toolCallPosition += 1) {
          final toolCall = toolCalls[toolCallPosition];
          if (toolCall is! Map) {
            continue;
          }
          final function = toolCall['function'];
          final toolCallIndex = _normalizeInt(toolCall['index']);
          final providerCallId = _normalizeText(toolCall['id']);
          String? toolName;
          String? argumentsDelta;
          if (function is Map) {
            toolName = _normalizeText(function['name']);
            argumentsDelta = _normalizeText(function['arguments']);
          }
          if (providerCallId != null || toolName != null) {
            yield StreamingPlannerChunk.toolCallStarted(
              toolCallIndex: toolCallIndex,
              providerCallId: providerCallId,
              toolName: toolName,
              providerMetadata: _providerStateFromChatCompletions(data),
            );
          }
          if (argumentsDelta != null) {
            yield StreamingPlannerChunk.toolCallArgumentsDelta(
              toolCallIndex: toolCallIndex,
              providerCallId: providerCallId,
              toolName: toolName,
              argumentsTextDelta: argumentsDelta,
              providerMetadata: _providerStateFromChatCompletions(data),
            );
          }
        }
      } catch (e) {
        Logger.e('OpenAiChatCompletionsRuntime', 'Chat Completions planner JSON解析错误: $e');
      }
    }
    yield const StreamingPlannerChunk.streamCompleted();
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

  int? _normalizeInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
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
