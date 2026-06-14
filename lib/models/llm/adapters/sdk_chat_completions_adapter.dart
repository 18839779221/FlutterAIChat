import 'dart:convert';

import 'package:openai_dart/openai_dart.dart' as oai;

import '../../../services/attachments/chat_attachment_payload_codec.dart';
import '../../../services/chat_service.dart';
import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';
import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_cache_request_options.dart';
import '../llm_cache_strategy.dart';
import '../llm_config.dart';
import '../llm_request_options.dart';
import '../runtime/protocol_request_spec.dart';
import '../streaming_decision_accumulator.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';
import '../api_protocol_resolver.dart';
import 'provider_capabilities.dart';

/// SDK-backed implementation of [ApiStyleAdapter] for the Chat Completions
/// protocol, powered by `openai_dart`.
///
/// This adapter uses the `openai_dart` package to build correct request
/// payloads and parse responses, avoiding manual JSON construction that
/// can miss provider-specific requirements (e.g., DeepSeek's strict
/// tool_calls message sequencing).
class SdkChatCompletionsAdapter extends ApiStyleAdapter {
  const SdkChatCompletionsAdapter();

  @override
  ApiStyle get style => ApiStyle.chatCompletions;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsPlannerStreaming: true,
        supportsParallelToolCalls: true,
        supportsImageInput: true,
        supportsPreUploadedFiles: false,
        supportsInlineBase64Images: false,
        supportsRemoteImageUrl: true,
      );

  @override
  Map<String, String> buildHeaders(LLMConfig runtimeConfig) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${runtimeConfig.apiKey}',
    };
  }

  @override
  ProtocolRequestSpec buildChatRequestSpec({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    required LLMConfig runtimeConfig,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    final request = _buildChatRequest(
      messages: messages,
      config: config,
      modelName: modelName,
      requestOptions: requestOptions,
    );
    return ChatCompletionsRequestSpec(request: request);
  }

  @override
  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    final request = _buildChatRequest(
      messages: messages,
      config: config,
      modelName: modelName,
      requestOptions: requestOptions,
    );
    // Serialize via toJson and strip null fields for clean payload
    return cleanNullsFromJson(request.toJson());
  }

  oai.ChatCompletionCreateRequest _buildChatRequest({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required LlmRequestOptions requestOptions,
  }) {
    final normalizedMessages = normalizeMessagesWithConfiguredSystemPrompt(
      messages,
      config.systemPrompt,
    );
    final sdkMessages = <oai.ChatMessage>[];
    for (final m in normalizedMessages) {
      final imageAttachments =
          ChatAttachmentPayloadCodec.imageAttachments(m.attachments);
      final imageReference = imageAttachments.isEmpty
          ? null
          : ChatAttachmentPayloadCodec.resolveImageReferenceForRuntime(
              imageAttachments.first,
            );
      if (m.role == MessageRole.system) {
        if (m.text.trim().isNotEmpty) {
          sdkMessages.add(oai.ChatMessage.system(m.text));
        }
        continue;
      }
      if (imageReference != null && m.role == MessageRole.user) {
        sdkMessages.add(
          oai.ChatMessage.fromJson({
            'role': 'user',
            'content': [
              if (m.text.trim().isNotEmpty)
                {
                  'type': 'text',
                  'text': m.text,
                },
              {
                'type': 'image_url',
                'image_url': {'url': imageReference},
              },
            ],
          }),
        );
        continue;
      }
      if (m.text.trim().isNotEmpty) {
        sdkMessages.add(
          switch (m.role) {
            MessageRole.user => oai.ChatMessage.user(m.text),
            MessageRole.assistant =>
              oai.ChatMessage.assistant(content: m.text),
            MessageRole.system => oai.ChatMessage.system(m.text),
          },
        );
      }
    }

    final payload = <String, dynamic>{
      'model': modelName,
      'messages': sdkMessages.map((message) => message.toJson()).toList(),
      if (requestOptions.maxOutputTokens != null)
        'max_completion_tokens': requestOptions.maxOutputTokens,
    };
    _applyCacheHints(payload, requestOptions.cache);
    return oai.ChatCompletionCreateRequest.fromJson(payload);
  }

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) {
    try {
      final completion = oai.ChatCompletion.fromJson(payload);
      final message = completion.choices.firstOrNull?.message;
      if (message == null) return null;

      // Check for tool calls first
      if (message.hasToolCalls) {
        final firstToolCall = message.toolCalls!.first;
        final args = _decodeArguments(firstToolCall.function.arguments);
        if (args != null) {
          return PlannerToolChoice.callTool(
            toolName: firstToolCall.function.name,
            arguments: args,
          );
        }
      }

      // Fall back to text content
      final content = _extractContentText(message);
      if (content != null) {
        return PlannerToolChoice.respond(content);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  String extractNonStreamText(Map<String, dynamic> payload) {
    try {
      final completion = oai.ChatCompletion.fromJson(payload);
      return completion.choices.firstOrNull?.message.content ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Parse a non-streaming [ChatCompletion] response into a
  /// [ModelTurnDecision] for the agent loop.
  ///
  /// Used by the streaming planner fallback path (non-SSE response).
  @override
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    final providerState = <String, dynamic>{
      if (payload['id'] is String && (payload['id'] as String).trim().isNotEmpty)
        'response_id': payload['id'],
    };
    final rawMessage = extractRawAssistantMessage(payload);
    if (rawMessage == null) {
      return null;
    }

    final toolCalls = _parseToolCalls(rawMessage);
    final contentParts = _extractContentParts(rawMessage['content']);
    final content = contentParts.content;
    final reasoning = _joinReasoningParts([
      rawMessage['reasoning_content'],
      rawMessage['reasoning'],
      rawMessage['thinking'],
      contentParts.reasoning,
    ]);

    if (toolCalls.isEmpty && content == null && reasoning == null) {
      return null;
    }

    return ModelTurnDecision(
      toolCalls: toolCalls,
      assistantMessage: content,
      visibleReasoning: reasoning,
      providerState: providerState,
      isTerminal: toolCalls.isEmpty,
    );
  }

  @override
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  ) {
    final choices = responsePayload['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    return Map<String, dynamic>.from(message);
  }

  @override
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    final hasContent = (snapshot.text ?? '').isNotEmpty;
    final hasReasoning = (snapshot.reasoning ?? '').isNotEmpty;
    final hasToolCalls = snapshot.toolCalls.isNotEmpty;
    if (!hasContent && !hasReasoning && !hasToolCalls) return null;

    return <String, dynamic>{
      'role': 'assistant',
      if (hasContent) 'content': snapshot.text,
      if (hasReasoning) 'reasoning_content': snapshot.reasoning,
      if (hasToolCalls)
        'tool_calls': [
          for (final tc in snapshot.toolCalls)
            {
              if (tc.id != null) 'id': tc.id,
              'type': 'function',
              'function': {
                'name': tc.toolName ?? '',
                'arguments': tc.argumentsBuffer,
              },
            },
        ],
    };
  }

  @override
  ProtocolRequestSpec buildPlannerRequestSpecFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    required LLMConfig runtimeConfig,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    final payload = buildPlannerPayloadFromCarriers(
      carriers: carriers,
      config: config,
      modelName: modelName,
      availableTools: availableTools,
      parallelToolCalls: parallelToolCalls,
      requestOptions: requestOptions,
    );
    return ChatCompletionsRequestSpec(
      request: oai.ChatCompletionCreateRequest.fromJson(payload),
    );
  }

  @override
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    final messages = <Map<String, dynamic>>[];

    for (final carrier in carriers) {
      switch (carrier) {
        case SyntheticCarrier(role: SyntheticRole.system, :final content):
          messages.add({'role': 'system', 'content': content});

        case SyntheticCarrier(role: SyntheticRole.user, :final content):
          messages.add({'role': 'user', 'content': content});

        case SyntheticCarrier(
              role: SyntheticRole.toolResult,
              :final toolCallId,
              :final content,
            ):
          messages.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': content,
          });

        case RawAssistantCarrier(:final rawJson):
          // Verbatim splice — this is the whole point of the architecture.
          messages.add(Map<String, dynamic>.from(rawJson));
      }
    }

    final tools = availableTools
        .map((t) => <String, dynamic>{
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.inputSchema,
              },
            })
        .toList(growable: false);

    final includeParallel = tools.isNotEmpty && !_isDeepSeekModel(modelName);
    final payload = <String, dynamic>{
      'model': modelName,
      'messages': messages,
      if (requestOptions.maxOutputTokens != null)
        'max_completion_tokens': requestOptions.maxOutputTokens,
      if (tools.isNotEmpty) ...{
        'tools': tools,
        'tool_choice': 'auto',
      },
      if (includeParallel) 'parallel_tool_calls': parallelToolCalls,
    };
    _applyCacheHints(payload, requestOptions.cache);
    return payload;
  }

  bool _isDeepSeekModel(String modelName) {
    return modelName.trim().toLowerCase().startsWith('deepseek');
  }

  void _applyCacheHints(
    Map<String, dynamic> payload,
    LlmCacheRequestOptions cache,
  ) {
    if (cache.strategy != LlmCacheStrategy.providerHints) {
      return;
    }
    if (cache.cacheKey != null && cache.cacheKey!.trim().isNotEmpty) {
      payload['prompt_cache_key'] = cache.cacheKey!.trim();
    }
    if (cache.retention != null && cache.retention!.trim().isNotEmpty) {
      payload['prompt_cache_retention'] = cache.retention!.trim();
    }
  }

  Map<String, dynamic>? _decodeArguments(String raw) {
    if (raw.isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  String? _extractContentText(oai.AssistantMessage message) {
    final content = message.content?.trim();
    if (content != null && content.isNotEmpty) return content;
    return null;
  }

  List<ModelToolCall> _parseToolCalls(Map<String, dynamic> message) {
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List || toolCalls.isEmpty) {
      return const [];
    }

    final parsed = <ModelToolCall>[];
    for (var i = 0; i < toolCalls.length; i++) {
      final rawToolCall = toolCalls[i];
      if (rawToolCall is! Map) {
        continue;
      }
      final normalizedToolCall = rawToolCall.cast<String, dynamic>();
      final function = normalizedToolCall['function'];
      if (function is! Map) {
        continue;
      }
      final normalizedFunction = function.cast<String, dynamic>();
      final toolName = normalizeText(normalizedFunction['name']);
      final arguments = decodeToolArguments(normalizedFunction['arguments']);
      if (toolName == null || arguments == null) {
        continue;
      }
      parsed.add(
        ModelToolCall(
          providerCallId: normalizeText(normalizedToolCall['id']),
          toolName: toolName,
          arguments: arguments,
          sequence: i,
        ),
      );
    }
    return parsed;
  }

  _ContentParts _extractContentParts(dynamic content) {
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final inlineText = _nonBlankText(content);
    if (inlineText != null) {
      final extracted = _extractThinkTaggedTextPreserveWhitespace(inlineText);
      if (extracted.reasoning != null) {
        reasoningBuffer.write(extracted.reasoning);
      }
      if (extracted.content != null) {
        textBuffer.write(extracted.content);
      }
      return _ContentParts(
        content: normalizeAggregatedText(textBuffer.toString()),
        reasoning: normalizeAggregatedText(reasoningBuffer.toString()),
      );
    }

    if (content is List) {
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final text = _nonBlankText(
          normalizedItem['text'] ?? normalizedItem['content'],
        );
        if (text == null) {
          continue;
        }
        final extracted = _extractThinkTaggedTextPreserveWhitespace(text);
        if (extracted.reasoning != null) {
          reasoningBuffer.write(extracted.reasoning);
        }
        if (extracted.content != null) {
          textBuffer.write(extracted.content);
        }
      }
    }

    return _ContentParts(
      content: normalizeAggregatedText(textBuffer.toString()),
      reasoning: normalizeAggregatedText(reasoningBuffer.toString()),
    );
  }

  String? _joinReasoningParts(List<dynamic> values) {
    final buffer = StringBuffer();
    for (final value in values) {
      final text = normalizeText(value);
      if (text != null) {
        buffer.write(text);
      }
    }
    return normalizeAggregatedText(buffer.toString());
  }

  String? _nonBlankText(dynamic value) {
    if (value is! String) {
      return null;
    }
    return value.trim().isEmpty ? null : value;
  }

  ThinkTagExtraction _extractThinkTaggedTextPreserveWhitespace(String value) {
    final matches = _thinkTagPattern.allMatches(value).toList(growable: false);
    if (matches.isEmpty) {
      return ThinkTagExtraction(content: value);
    }

    final reasoningBuffer = StringBuffer();
    for (final match in matches) {
      final reasoning = normalizeText(match.group(1));
      if (reasoning != null) {
        reasoningBuffer.write(reasoning);
      }
    }

    final content = value.replaceAll(_thinkTagPattern, '');
    return ThinkTagExtraction(
      content: content.trim().isEmpty ? null : content,
      reasoning: normalizeAggregatedText(reasoningBuffer.toString()),
    );
  }

  static final RegExp _thinkTagPattern = RegExp(
    r'<think>([\s\S]*?)</think>',
    caseSensitive: false,
  );

}

class _ContentParts {
  const _ContentParts({this.content, this.reasoning});

  final String? content;
  final String? reasoning;
}
