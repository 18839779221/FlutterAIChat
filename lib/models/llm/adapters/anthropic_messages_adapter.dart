import 'dart:convert';

import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';
import '../../../services/attachments/chat_attachment_payload_codec.dart';
import '../../chat/chat_attachment.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_cache_request_options.dart';
import '../llm_cache_strategy.dart';
import '../llm_request_options.dart';
import '../runtime/protocol_request_spec.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../llm_request_purpose.dart';
import '../streaming_decision_accumulator.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';
import 'provider_capabilities.dart';

/// Deprecated self-managed semantic adapter for the Anthropic Messages
/// protocol.
///
/// Anthropic 目标主链路已经是 SDK-first / runtime-first。
/// 这个自研实现仅为迁移期兼容保留，不再维护；后续 provider 能力、
/// 缓存兼容与真实请求优化都不应继续落在这里。
@Deprecated(
  'Anthropic 主链路目标为 SDK-first；AnthropicMessagesAdapter 仅为迁移期兼容保留，不再维护。',
)
class AnthropicMessagesAdapter extends ApiStyleAdapter {
  const AnthropicMessagesAdapter();

  @override
  ApiStyle get style => ApiStyle.anthropicMessages;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsPlannerStreaming: true,
        supportsParallelToolCalls: true,
        supportsImageInput: true,
        supportsPreUploadedFiles: false,
        supportsInlineBase64Images: true,
        supportsRemoteImageUrl: false,
      );

  @override
  Map<String, String> buildHeaders(LLMConfig runtimeConfig) {
    return {
      'Content-Type': 'application/json',
      'x-api-key': runtimeConfig.apiKey,
      'anthropic-version': '2023-06-01',
    };
  }

  @override
  LlmRequestOptions normalizeRequestOptions(
    LlmRequestOptions requestOptions, {
    required LlmRequestPurpose purpose,
  }) {
    final allowReasoning = switch (purpose) {
      LlmRequestPurpose.planner => false,
      LlmRequestPurpose.summary ||
      LlmRequestPurpose.webpageProcessing ||
      LlmRequestPurpose.sideTask => true,
    };
    if (requestOptions.allowReasoning == allowReasoning) {
      return requestOptions;
    }
    return LlmRequestOptions(
      maxOutputTokens: requestOptions.maxOutputTokens,
      allowReasoning: allowReasoning,
      cache: requestOptions.cache,
    );
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
    return JsonProtocolRequestSpec(
      payload: _buildMessagesPayload(
        messages: messages,
        config: config,
        modelName: modelName,
        stream: stream,
        requestOptions: requestOptions,
      ),
      headers: buildHeaders(runtimeConfig),
    );
  }

  @override
  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    return _buildMessagesPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: stream,
      requestOptions: requestOptions,
    );
  }

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) {
      return null;
    }
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] == 'tool_use') {
        final toolName = normalizeText(normalizedItem['name']);
        final arguments = decodeToolArguments(normalizedItem['input']);
        if (toolName != null && arguments != null) {
          return PlannerToolChoice.callTool(
            toolName: toolName,
            arguments: arguments,
          );
        }
      }
      final response = extractContentText(normalizedItem);
      if (response != null) {
        return PlannerToolChoice.respond(response);
      }
    }
    return null;
  }

  @override
  String extractNonStreamText(Map<String, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) {
      return '';
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final text = extractContentText(item.cast<String, dynamic>());
      if (text != null) {
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  @override
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    final content = payload['content'];
    final providerState = <String, dynamic>{
      if (payload['id'] is String && (payload['id'] as String).trim().isNotEmpty)
        'message_id': payload['id'],
      if (content is List)
        'content_blocks': content
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
    };
    if (content is! List) {
      return null;
    }

    final toolCalls = <ModelToolCall>[];
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      final item = content[i];
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] == 'tool_use') {
        final toolName = normalizeText(normalizedItem['name']);
        final input = normalizedItem['input'];
        if (toolName == null || input is! Map) {
          continue;
        }
        toolCalls.add(
          ModelToolCall(
            providerCallId: normalizeText(normalizedItem['id']),
            toolName: toolName,
            arguments: input.cast<String, dynamic>(),
            sequence: i,
          ),
        );
        continue;
      }

      final type = normalizedItem['type'];
      if (type == 'thinking' || type == 'redacted_thinking') {
        final thinking = normalizeText(
          normalizedItem['thinking'] ?? normalizedItem['text'],
        );
        if (thinking != null) {
          reasoningBuffer.write(thinking);
        }
        continue;
      }

      final text = _extractContentTextPreserveWhitespace(normalizedItem);
      if (text != null) {
        textBuffer.write(text);
      }
    }

    final visibleReasoning = _normalizeAggregatedText(reasoningBuffer.toString());

    if (toolCalls.isNotEmpty) {
      return ModelTurnDecision(
        toolCalls: toolCalls,
        assistantMessage: null,
        visibleReasoning: visibleReasoning,
        providerState: providerState,
        isTerminal: false,
      );
    }

    final assistantMessage = _normalizeAggregatedText(textBuffer.toString());
    if (assistantMessage == null) {
      return null;
    }
    return ModelTurnDecision(
      toolCalls: const [],
      assistantMessage: assistantMessage,
      visibleReasoning: visibleReasoning,
      providerState: providerState,
      isTerminal: true,
    );
  }

  /// Extracts plain text from an Anthropic content block. Public so other
  /// adapters / tests can reuse it.
  static String? extractContentText(Map<String, dynamic> item) {
    final type = item['type'];
    if (type != 'text' && type != 'thinking' && type != 'redacted_thinking') {
      return null;
    }
    final text = normalizeText(item['text'] ?? item['thinking']);
    return text;
  }

  String? _extractContentTextPreserveWhitespace(Map<String, dynamic> item) {
    final type = item['type'];
    if (type != 'text') {
      return null;
    }
    final value = item['text'];
    if (value is! String) {
      return null;
    }
    return value.trim().isEmpty ? null : value;
  }

  String? _normalizeAggregatedText(String value) {
    return value.trim().isEmpty ? null : value;
  }

  Map<String, dynamic> _buildMessagesPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    required LlmRequestOptions requestOptions,
  }) {
    final systemSegments = <String>[];
    final configuredSystemPrompt = config.systemPrompt.trim();
    if (configuredSystemPrompt.isNotEmpty) {
      systemSegments.add(configuredSystemPrompt);
    }

    final normalizedMessages = <Map<String, dynamic>>[];
    for (final message in messages) {
      final trimmedText = message.text.trim();
      if (trimmedText.isEmpty) {
        continue;
      }
      if (message.role == MessageRole.system) {
        systemSegments.add(trimmedText);
        continue;
      }
      normalizedMessages.add(
        _buildMessage(message),
      );
    }

    final payload = <String, dynamic>{
      'model': modelName,
      if (systemSegments.isNotEmpty) 'system': systemSegments.join('\n\n'),
      'messages': normalizedMessages,
      'stream': stream,
      if (requestOptions.maxOutputTokens != null)
        'max_tokens': requestOptions.maxOutputTokens,
      if (!requestOptions.allowReasoning)
        'thinking': const {'type': 'disabled'},
    };
    _applyCacheHints(payload, requestOptions.cache);
    return payload;
  }

  Map<String, dynamic> _buildMessage(ChatMessage message) {
    final contextType = modelContextTypeOf(message);
    if (contextType == assistantToolUseContextType) {
      final providerCallId = providerCallIdOf(message);
      final toolName = toolNameOf(message);
      if (toolName != null && providerCallId != null) {
        return {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': providerCallId,
              'name': toolName,
              'input': toolArgumentsOf(message) ?? const {},
            },
          ],
        };
      }
    }
    if (contextType == userToolResultContextType) {
      final providerCallId = providerCallIdOf(message);
      if (providerCallId != null) {
        return {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': providerCallId,
              'content': [
                {
                  'type': 'text',
                  'text': message.text,
                },
              ],
            },
          ],
        };
      }
    }
    return {
      'role': message.role == MessageRole.assistant ? 'assistant' : 'user',
      'content': [
        {
          'type': 'text',
          'text': message.text,
        },
      ],
    };
  }

  @override
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  ) {
    if (responsePayload['role'] != 'assistant') return null;
    final content = responsePayload['content'];
    if (content is! List || content.isEmpty) return null;
    return <String, dynamic>{
      'role': 'assistant',
      'content': List<dynamic>.from(content),
    };
  }

  @override
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    final blocks = <Map<String, dynamic>>[];

    final reasoning = snapshot.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      final signature =
          snapshot.providerState['anthropic_thinking_signature']?.toString() ?? '';
      blocks.add({
        'type': 'thinking',
        'thinking': reasoning,
        'signature': signature,
      });
    }

    final text = snapshot.text;
    if (text != null && text.isNotEmpty) {
      blocks.add({'type': 'text', 'text': text});
    }

    for (final tc in snapshot.toolCalls) {
      if (tc.id == null || tc.toolName == null) continue;
      blocks.add({
        'type': 'tool_use',
        'id': tc.id,
        'name': tc.toolName,
        'input': _safeDecodeArgs(tc.argumentsBuffer),
      });
    }

    if (blocks.isEmpty) return null;
    return {'role': 'assistant', 'content': blocks};
  }

  Map<String, dynamic> _safeDecodeArgs(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
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
    return JsonProtocolRequestSpec(
      payload: buildPlannerPayloadFromCarriers(
        carriers: carriers,
        config: config,
        modelName: modelName,
        availableTools: availableTools,
        parallelToolCalls: parallelToolCalls,
        requestOptions: requestOptions,
      ),
      headers: buildHeaders(runtimeConfig),
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
    String? systemText;
    final messages = <Map<String, dynamic>>[];
    List<Map<String, dynamic>>? pendingToolResults;

    void flushPendingToolResults() {
      final blocks = pendingToolResults;
      if (blocks == null || blocks.isEmpty) {
        pendingToolResults = null;
        return;
      }
      messages.add({
        'role': 'user',
        'content': List<Map<String, dynamic>>.from(blocks),
      });
      pendingToolResults = null;
    }

    for (final carrier in carriers) {
      switch (carrier) {
        case SyntheticCarrier(role: SyntheticRole.system, :final content):
          flushPendingToolResults();
          systemText = systemText == null ? content : '$systemText\n\n$content';

        case SyntheticCarrier(role: SyntheticRole.user, :final content):
          flushPendingToolResults();
          messages.add({
            'role': 'user',
            'content': _buildUserContentParts(
              content: content,
              attachments: carrier.attachments,
            ),
          });

        case SyntheticCarrier(
              role: SyntheticRole.toolResult,
              :final toolCallId,
              :final content,
            ):
          (pendingToolResults ??= <Map<String, dynamic>>[]).add({
            'type': 'tool_result',
            'tool_use_id': toolCallId,
            'content': [
              {
                'type': 'text',
                'text': content,
              },
            ],
          });

        case RawAssistantCarrier(:final rawJson):
          flushPendingToolResults();
          messages.add(Map<String, dynamic>.from(rawJson));
      }
    }

    flushPendingToolResults();

    final tools = availableTools
        .map((t) => <String, dynamic>{
              'name': t.name,
              'description': t.description,
              'input_schema': t.inputSchema,
            })
        .toList(growable: false);

    return <String, dynamic>{
      'model': modelName,
      if (systemText != null) 'system': systemText,
      'messages': messages,
      'max_tokens': requestOptions.maxOutputTokens ?? 4096,
      if (tools.isNotEmpty) 'tools': tools,
      if (!requestOptions.allowReasoning)
        'thinking': const {'type': 'disabled'},
    };
  }

  List<Map<String, dynamic>> _buildUserContentParts({
    required String content,
    required List<ChatAttachment> attachments,
  }) {
    final parts = <Map<String, dynamic>>[];
    if (content.trim().isNotEmpty) {
      parts.add({'type': 'text', 'text': content});
    }
    parts.addAll(
      ChatAttachmentPayloadCodec.imageAttachments(attachments).map((attachment) {
        final imageReference =
            ChatAttachmentPayloadCodec.resolveImageReference(attachment);
        if (imageReference == null) {
          return null;
        }
        final dataUrlMatch = RegExp(
          r'^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$',
        ).firstMatch(imageReference);
        if (dataUrlMatch != null) {
          return <String, dynamic>{
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': dataUrlMatch.group(1),
              'data': dataUrlMatch.group(2),
            },
          };
        }
        return <String, dynamic>{
          'type': 'image',
          'source': {
            'type': 'url',
            'url': imageReference,
          },
        };
      }).whereType<Map<String, dynamic>>(),
    );
    return parts;
  }

  void _applyCacheHints(
    Map<String, dynamic> payload,
    LlmCacheRequestOptions cache,
  ) {
    if (cache.strategy != LlmCacheStrategy.providerHints) {
      return;
    }
    if (!cache.markStableSystemPrefix) {
      return;
    }

    final systemValue = payload['system'];
    if (systemValue is! String || systemValue.trim().isEmpty) {
      return;
    }

    payload['system'] = [
      {
        'type': 'text',
        'text': systemValue,
        'cache_control': {'type': 'ephemeral'},
      },
    ];
  }
}
