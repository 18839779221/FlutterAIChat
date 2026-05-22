import 'dart:convert';

import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_cache_request_options.dart';
import '../llm_cache_strategy.dart';
import '../llm_request_options.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import '../streaming_decision_accumulator.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';

/// Legacy adapter for the OpenAI-compatible Chat Completions protocol.
///
/// Kept as a fallback when the SDK-backed [SdkChatCompletionsAdapter]
/// encounters issues with specific providers.
class LegacyChatCompletionsAdapter extends ApiStyleAdapter {
  const LegacyChatCompletionsAdapter();

  @override
  ApiStyle get style => ApiStyle.chatCompletions;

  @override
  Map<String, String> buildHeaders(LLMConfig runtimeConfig) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${runtimeConfig.apiKey}',
    };
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
  Map<String, dynamic> buildPlannerPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    final payload = buildChatPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: false,
      requestOptions: requestOptions,
    );
    final tools = availableTools
        .map(
          (tool) => {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputSchema,
            },
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = 'auto';
      // DeepSeek API rejects `parallel_tool_calls` with a 400 error;
      // only include it for providers that accept it (e.g. OpenAI).
      if (!_isDeepSeekModel(modelName)) {
        payload['parallel_tool_calls'] = parallelToolCalls;
      }
    }
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

  /// DeepSeek API rejects `parallel_tool_calls`; detect by model name prefix.
  static bool _isDeepSeekModel(String modelName) {
    return modelName.trim().toLowerCase().startsWith('deepseek');
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
