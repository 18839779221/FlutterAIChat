import 'dart:convert';

import 'package:openai_dart/openai_dart.dart' as oai;

import '../../../services/attachments/chat_attachment_payload_codec.dart';
import '../../../services/chat_service.dart';
import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';
import '../../chat/chat_attachment.dart';
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
import '../../../utils/logger.dart';

/// SDK-backed implementation of [ApiStyleAdapter] for the OpenAI Responses
/// protocol, powered by `openai_dart`.
///
/// This adapter uses the `openai_dart` package to build correct request
/// payloads and parse responses, avoiding manual JSON construction.
class SdkResponsesAdapter extends ApiStyleAdapter {
  const SdkResponsesAdapter();

  static const _tag = 'SdkResponsesAdapter';

  static const Map<String, dynamic> _reasoningConfig = {
    'effort': 'medium',
    'summary': 'auto',
  };

  @override
  ApiStyle get style => ApiStyle.responses;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsPlannerStreaming: true,
        supportsParallelToolCalls: true,
        supportsImageInput: true,
        supportsPreUploadedFiles: true,
        supportsInlineBase64Images: true,
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
    final request = _buildResponsesRequest(
      messages: messages,
      config: config,
      modelName: modelName,
      requestOptions: requestOptions,
    );
    return ResponsesRequestSpec(request: request);
  }

  @override
  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    final request = _buildResponsesRequest(
      messages: messages,
      config: config,
      modelName: modelName,
      requestOptions: requestOptions,
    );
    return cleanNullsFromJson(request.toJson());
  }

  oai.CreateResponseRequest _buildResponsesRequest({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required LlmRequestOptions requestOptions,
  }) {
    final normalizedMessages = normalizeMessagesWithConfiguredSystemPrompt(
      messages,
      config.systemPrompt,
    );

    final input =
        normalizedMessages.map((msg) => _buildInputItem(msg)).toList();

    final payload = <String, dynamic>{
      'model': modelName,
      'input': input,
      'reasoning': _reasoningConfig,
      'store': false,
      if (requestOptions.maxOutputTokens != null)
        'max_output_tokens': requestOptions.maxOutputTokens,
    };
    _applyCacheHints(payload, requestOptions.cache);
    return oai.CreateResponseRequest.fromJson(payload);
  }

  Map<String, dynamic> _buildInputItem(ChatMessage message) {
    final contextType = modelContextTypeOf(message);
    if (contextType == assistantToolUseContextType) {
      final providerCallId = providerCallIdOf(message);
      final toolName = toolNameOf(message);
      if (toolName != null && providerCallId != null) {
        return {
          'type': 'function_call',
          'call_id': providerCallId,
          'name': toolName,
          'arguments': jsonEncode(toolArgumentsOf(message) ?? const {}),
        };
      }
    }
    if (contextType == userToolResultContextType) {
      final providerCallId = providerCallIdOf(message);
      if (providerCallId != null) {
        return {
          'type': 'function_call_output',
          'call_id': providerCallId,
          'output': message.text,
        };
      }
    }
    final imageAttachments =
        ChatAttachmentPayloadCodec.imageAttachments(message.attachments);
    final resolvedImageReferences = imageAttachments
        .map(ChatAttachmentPayloadCodec.resolveImageReferenceForRuntime)
        .toList(growable: false);
    final imageParts = resolvedImageReferences
        .map((imageReference) {
          if (imageReference == null) {
            return null;
          }
          return <String, dynamic>{
            'type': 'input_image',
            'image_url': imageReference,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (message.role == MessageRole.user) {
      Logger.temp(
        _tag,
        'attachments.responses_input_item_built',
        reason: 'diagnose_image_attachment_context_chain',
        data: {
          'textLength': message.text.length,
          'attachmentCount': message.attachments.length,
          'imageAttachmentCount': imageAttachments.length,
          'resolvedImageReferenceCount': resolvedImageReferences
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .length,
          'inputImagePartCount': imageParts.length,
          'localIds': message.attachments
              .map((attachment) => attachment.localId)
              .toList(),
          'hasProviderDataUrl': message.attachments
              .map(
                (attachment) =>
                    attachment.providerFileRefJson?['data_url'] is String &&
                    (attachment.providerFileRefJson?['data_url'] as String)
                        .trim()
                        .isNotEmpty,
              )
              .toList(),
          'resolvedReferenceKinds': resolvedImageReferences.map((value) {
            if (value == null || value.trim().isEmpty) {
              return 'missing';
            }
            if (value.startsWith('data:')) {
              return 'data_url';
            }
            if (value.startsWith('http://') || value.startsWith('https://')) {
              return 'remote_url';
            }
            return 'local_path';
          }).toList(),
          'modelContextType': modelContextTypeOf(message),
        },
      );
    }
    return {
      'type': 'message',
      'role': message.role.toString().split('.').last,
      'content': [
        {
          'type': message.role == MessageRole.assistant
              ? 'output_text'
              : 'input_text',
          'text': message.text,
        },
        ...imageParts,
      ],
    };
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

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) {
    final output = payload['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        final normalizedItem = item.cast<String, dynamic>();
        final type = normalizedItem['type'];
        if (type == 'function_call') {
          final toolCallChoice = _parseToolCall(normalizedItem);
          if (toolCallChoice != null) return toolCallChoice;
        }
        if (type == 'message') {
          final response = _extractMessageText(normalizedItem);
          if (response != null) {
            return PlannerToolChoice.respond(response);
          }
        }
      }
    }

    final outputText = normalizeText(payload['output_text']);
    if (outputText != null) {
      return PlannerToolChoice.respond(outputText);
    }
    return null;
  }

  @override
  String extractNonStreamText(Map<String, dynamic> payload) {
    final outputText = normalizeText(payload['output_text']);
    if (outputText != null) return outputText;
    final output = payload['output'];
    if (output is List) {
      final buffer = StringBuffer();
      for (final item in output) {
        if (item is! Map) continue;
        final normalizedItem = item.cast<String, dynamic>();
        if (normalizedItem['type'] != 'message') continue;
        final text = _extractMessageText(normalizedItem);
        if (text != null) buffer.write(text);
      }
      return buffer.toString();
    }
    return '';
  }

  @override
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    final providerState = <String, dynamic>{
      if (payload['id'] is String &&
          (payload['id'] as String).trim().isNotEmpty)
        'response_id': payload['id'],
    };

    final output = payload['output'];
    if (output is List) {
      final toolCalls = <ModelToolCall>[];
      final assistantBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      for (var i = 0; i < output.length; i++) {
        final item = output[i];
        if (item is! Map) continue;
        final normalizedItem = item.cast<String, dynamic>();
        switch (normalizedItem['type']) {
          case 'function_call':
            final toolName = normalizeText(normalizedItem['name']);
            final arguments = decodeToolArguments(normalizedItem['arguments']);
            final providerCallId = normalizeText(
              normalizedItem['call_id'] ?? normalizedItem['id'],
            );
            if (toolName != null && arguments != null) {
              toolCalls.add(
                ModelToolCall(
                  providerCallId: providerCallId,
                  toolName: toolName,
                  arguments: arguments,
                  sequence: i,
                ),
              );
            }
          case 'message':
            final text =
                _extractMessageText(normalizedItem, preserveWhitespace: true);
            if (text != null) assistantBuffer.write(text);
          case 'reasoning':
            final directText = normalizeText(
              normalizedItem['text'] ?? normalizedItem['content'],
            );
            if (directText != null) reasoningBuffer.write(directText);
            final summary = normalizedItem['summary'];
            if (summary is List) {
              for (final entry in summary) {
                if (entry is! Map) continue;
                final normalizedEntry = entry.cast<String, dynamic>();
                final summaryText = normalizeText(
                  normalizedEntry['text'] ?? normalizedEntry['summary_text'],
                );
                if (summaryText != null) reasoningBuffer.write(summaryText);
              }
            }
        }
      }

      final assistantMessage =
          normalizeAggregatedText(assistantBuffer.toString());
      final visibleReasoning =
          normalizeAggregatedText(reasoningBuffer.toString());
      if (toolCalls.isNotEmpty ||
          assistantMessage != null ||
          visibleReasoning != null) {
        return ModelTurnDecision(
          toolCalls: toolCalls,
          assistantMessage: assistantMessage,
          visibleReasoning: visibleReasoning,
          providerState: providerState,
          isTerminal: toolCalls.isEmpty,
        );
      }
    }

    final outputText = normalizeText(payload['output_text']);
    if (outputText != null) {
      return ModelTurnDecision(
        toolCalls: const [],
        assistantMessage: outputText,
        visibleReasoning: normalizeText(payload['reasoning']),
        providerState: providerState,
        isTerminal: true,
      );
    }
    return null;
  }

  PlannerToolChoice? _parseToolCall(Map<String, dynamic> item) {
    final toolName = normalizeText(item['name']);
    final arguments = decodeToolArguments(item['arguments']);
    if (toolName == null || arguments == null) return null;
    return PlannerToolChoice.callTool(
      toolName: toolName,
      arguments: arguments,
    );
  }

  String? _extractMessageText(
    Map<String, dynamic> item, {
    bool preserveWhitespace = false,
  }) {
    final content = item['content'];
    if (content is! List) return null;

    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) continue;
      final normalizedPart = part.cast<String, dynamic>();
      if (normalizedPart['type'] != 'output_text') continue;
      final text = preserveWhitespace
          ? _nonBlankTextPreserveWhitespace(normalizedPart['text'])
          : normalizeText(normalizedPart['text']);
      if (text != null) buffer.write(text);
    }

    final aggregated = buffer.toString().trim();
    return aggregated.isEmpty ? null : aggregated;
  }

  String? _nonBlankTextPreserveWhitespace(dynamic value) {
    if (value is! String) return null;
    return value.trim().isEmpty ? null : value;
  }

  @override
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  ) {
    final output = responsePayload['output'];
    if (output is! List || output.isEmpty) return null;
    return {'output': List<dynamic>.from(output)};
  }

  @override
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    final items = <Map<String, dynamic>>[];

    final reasoning = snapshot.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      items.add({
        'type': 'reasoning',
        'summary': [
          {'type': 'summary_text', 'text': reasoning},
        ],
      });
    }

    final text = snapshot.text;
    if (text != null && text.isNotEmpty) {
      items.add({
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': text},
        ],
      });
    }

    for (final tc in snapshot.toolCalls) {
      if (tc.id == null || tc.toolName == null) continue;
      items.add({
        'type': 'function_call',
        'call_id': tc.id,
        'name': tc.toolName,
        'arguments': tc.argumentsBuffer,
      });
    }

    if (items.isEmpty) return null;
    return {'output': items};
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
    return ResponsesRequestSpec(
      request: oai.CreateResponseRequest.fromJson(payload),
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
    String? instructions;
    final input = <Map<String, dynamic>>[];

    for (final carrier in carriers) {
      switch (carrier) {
        case SyntheticCarrier(role: SyntheticRole.system, :final content):
          instructions =
              instructions == null ? content : '$instructions\n\n$content';

        case SyntheticCarrier(
            role: SyntheticRole.user,
            :final content,
            :final attachments,
          ):
          input.add({
            'type': 'message',
            'role': 'user',
            'content': _buildPlannerUserContentParts(
              content: content,
              attachments: attachments,
            ),
          });

        case SyntheticCarrier(
            role: SyntheticRole.toolResult,
            :final toolCallId,
            :final content,
          ):
          input.add({
            'type': 'function_call_output',
            'call_id': toolCallId,
            'output': content,
          });

        case RawAssistantCarrier(:final rawJson):
          final outputs = rawJson['output'];
          if (outputs is List) {
            for (final item in outputs) {
              if (item is Map) {
                input.add(Map<String, dynamic>.from(item));
              }
            }
          }
      }
    }

    final tools = availableTools
        .map((t) => <String, dynamic>{
              'type': 'function',
              'name': t.name,
              'description': t.description,
              'parameters': t.inputSchema,
            })
        .toList(growable: false);

    final payload = <String, dynamic>{
      'model': modelName,
      if (instructions != null) 'instructions': instructions,
      'input': input,
      'store': false,
      if (tools.isNotEmpty) 'tools': tools,
    };
    _applyCacheHints(payload, requestOptions.cache);
    return payload;
  }

  List<Map<String, dynamic>> _buildPlannerUserContentParts({
    required String content,
    required List<ChatAttachment> attachments,
  }) {
    final parts = <Map<String, dynamic>>[];
    if (content.trim().isNotEmpty) {
      parts.add({'type': 'input_text', 'text': content});
    }
    parts.addAll(
      ChatAttachmentPayloadCodec.imageAttachments(attachments)
          .map((attachment) {
        final imageReference =
            ChatAttachmentPayloadCodec.resolveImageReference(attachment);
        if (imageReference == null || imageReference.trim().isEmpty) {
          return null;
        }
        return <String, dynamic>{
          'type': 'input_image',
          'image_url': imageReference,
        };
      }).whereType<Map<String, dynamic>>(),
    );
    return parts;
  }
}
