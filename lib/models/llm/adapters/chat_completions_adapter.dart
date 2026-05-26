import 'dart:convert';

import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_cache_request_options.dart';
import '../llm_cache_strategy.dart';
import '../llm_request_options.dart';
import '../runtime/protocol_request_spec.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../streaming_decision_accumulator.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';
import 'provider_capabilities.dart';

/// Deprecated legacy adapter for the OpenAI-compatible Chat Completions
/// protocol.
///
/// Provider 主链路已经切到 SDK-backed [SdkChatCompletionsAdapter]。
/// 这个自研实现只保留为极端兼容问题下的临时 fallback，不再维护，
/// 后续 provider 能力或缓存相关优化不要继续加在这里。
@Deprecated(
  'Chat Completions 主链路已切到 SDK；LegacyChatCompletionsAdapter 仅保留为临时 fallback，不再维护。',
)
class LegacyChatCompletionsAdapter extends ApiStyleAdapter {
  const LegacyChatCompletionsAdapter();

  @override
  ApiStyle get style => ApiStyle.chatCompletions;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsPlannerStreaming: true,
        supportsParallelToolCalls: true,
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
    return JsonProtocolRequestSpec(
      payload: buildChatPayload(
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
    final normalizedMessages = normalizeMessagesWithConfiguredSystemPrompt(
        messages, config.systemPrompt);
    final payload = {
      'model': modelName,
      'messages': normalizedMessages
          .map(
            (msg) => _buildMessage(msg),
          )
          .toList(),
      'stream': stream,
    };
    _applyCacheHints(payload, requestOptions.cache);
    return payload;
  }

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return null;
    }

    final message = firstChoice['message'];
    if (message is! Map) {
      return null;
    }

    final normalizedMessage = message.cast<String, dynamic>();
    final toolCallChoice = _parseToolCall(normalizedMessage);
    if (toolCallChoice != null) {
      return toolCallChoice;
    }

    final content = _extractMessageText(normalizedMessage);
    if (content != null) {
      return PlannerToolChoice.respond(content);
    }

    return null;
  }

  @override
  String extractNonStreamText(Map<String, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      return '';
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return '';
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      return '';
    }
    return _extractMessageText(message.cast<String, dynamic>()) ?? '';
  }

  @override
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    final providerState = <String, dynamic>{
      if (payload['id'] is String && (payload['id'] as String).trim().isNotEmpty)
        'response_id': payload['id'],
    };
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return null;
    }

    final message = firstChoice['message'];
    if (message is! Map) {
      return null;
    }

    final normalizedMessage = message.cast<String, dynamic>();
    final toolCalls = <ModelToolCall>[];
    final rawToolCalls = normalizedMessage['tool_calls'];
    if (rawToolCalls is List) {
      for (var i = 0; i < rawToolCalls.length; i++) {
        final rawToolCall = rawToolCalls[i];
        if (rawToolCall is! Map) {
          continue;
        }
        final function = rawToolCall['function'];
        if (function is! Map) {
          continue;
        }
        final toolName = normalizeText(function['name']);
        final arguments = decodeToolArguments(function['arguments']);
        if (toolName == null || arguments == null) {
          continue;
        }
        toolCalls.add(
          ModelToolCall(
            providerCallId: normalizeText(rawToolCall['id']),
            toolName: toolName,
            arguments: arguments,
            sequence: i,
          ),
        );
      }
    }

    final content = _extractMessageText(normalizedMessage);
    final visibleReasoning = _extractReasoningText(normalizedMessage);
    if (toolCalls.isEmpty && content == null && visibleReasoning == null) {
      return null;
    }

    return ModelTurnDecision(
      toolCalls: toolCalls,
      assistantMessage: content,
      visibleReasoning: visibleReasoning,
      providerState: providerState,
      isTerminal: toolCalls.isEmpty,
    );
  }

  Map<String, dynamic> _buildMessage(ChatMessage message) {
    final contextType = modelContextTypeOf(message);
    if (contextType == assistantToolUseContextType) {
      final providerCallId = providerCallIdOf(message);
      final toolName = toolNameOf(message);
      if (toolName != null && providerCallId != null) {
        return {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': providerCallId,
              'type': 'function',
              'function': {
                'name': toolName,
                'arguments': jsonEncode(toolArgumentsOf(message) ?? const {}),
              },
            },
          ],
        };
      }
    }
    if (contextType == userToolResultContextType) {
      final providerCallId = providerCallIdOf(message);
      if (providerCallId != null) {
        return {
          'role': 'tool',
          'tool_call_id': providerCallId,
          'content': message.text,
        };
      }
    }
    return {
      'role': message.role.toString().split('.').last,
      'content': message.text,
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

  PlannerToolChoice? _parseToolCall(Map<String, dynamic> message) {
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List || toolCalls.isEmpty) {
      return null;
    }

    final firstToolCall = toolCalls.first;
    if (firstToolCall is! Map) {
      return null;
    }

    final function = firstToolCall['function'];
    if (function is! Map) {
      return null;
    }

    final toolName = normalizeText(function['name']);
    final arguments = decodeToolArguments(function['arguments']);
    if (toolName == null || arguments == null) {
      return null;
    }

    return PlannerToolChoice.callTool(
      toolName: toolName,
      arguments: arguments,
    );
  }

  String? _extractMessageText(Map<String, dynamic> message) {
    final content = message['content'];
    final inlineText = normalizeText(content);
    if (inlineText != null) {
      return extractThinkTaggedText(inlineText).content;
    }

    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final text = normalizeText(
          normalizedItem['text'] ?? normalizedItem['content'],
        );
        if (text != null) {
          final extracted = extractThinkTaggedText(text);
          if (extracted.content != null) {
            buffer.write(extracted.content);
          }
        }
      }
      final aggregated = buffer.toString().trim();
      if (aggregated.isNotEmpty) {
        return aggregated;
      }
    }

    return null;
  }

  String? _extractReasoningText(Map<String, dynamic> message) {
    final buffer = StringBuffer();
    final directReasoning = normalizeText(
      message['reasoning_content'] ?? message['reasoning'] ?? message['thinking'],
    );
    if (directReasoning != null) {
      buffer.write(directReasoning);
    }

    final content = message['content'];
    if (content is String) {
      final extracted = extractThinkTaggedText(content);
      if (extracted.reasoning != null) {
        buffer.write(extracted.reasoning);
      }
    } else if (content is List) {
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final text = normalizeText(
          normalizedItem['text'] ?? normalizedItem['content'],
        );
        if (text == null) {
          continue;
        }
        final extracted = extractThinkTaggedText(text);
        if (extracted.reasoning != null) {
          buffer.write(extracted.reasoning);
        }
      }
    }

    return normalizeText(buffer.toString());
  }

  @override
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  ) {
    // Legacy adapter is going away; mirror SDK adapter's shape if ever needed.
    throw UnimplementedError('legacy adapter does not participate in raw round-trip');
  }

  @override
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    throw UnimplementedError('legacy adapter does not participate in raw round-trip');
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
    throw UnimplementedError('legacy adapter does not participate in carrier-based path');
  }
}
