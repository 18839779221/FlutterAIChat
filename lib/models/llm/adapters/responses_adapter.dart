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

/// Adapter for the OpenAI Responses protocol.
class ResponsesAdapter extends ApiStyleAdapter {
  const ResponsesAdapter();
  static const Map<String, dynamic> _reasoningConfig = {
    'effort': 'medium',
    'summary': 'auto',
  };

  @override
  ApiStyle get style => ApiStyle.responses;

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
      'input': normalizedMessages
          .map(
            (msg) => _buildInputItem(msg),
          )
          .toList(),
      'reasoning': _reasoningConfig,
      'stream': stream,
      'store': false,
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
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.inputSchema,
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = 'auto';
      payload['parallel_tool_calls'] = parallelToolCalls;
    }
    _applyCacheHints(payload, requestOptions.cache);
    return payload;
  }

  @override
  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload) {
    final output = payload['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final type = normalizedItem['type'];
        if (type == 'function_call') {
          final toolCallChoice = _parseToolCall(normalizedItem);
          if (toolCallChoice != null) {
            return toolCallChoice;
          }
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
    if (outputText != null) {
      return outputText;
    }
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
    return {
      'role': message.role.toString().split('.').last,
      'content': [
        {
          'type': message.role == MessageRole.assistant
              ? 'output_text'
              : 'input_text',
          'text': message.text,
        },
      ],
    };
  }

  PlannerToolChoice? _parseToolCall(Map<String, dynamic> item) {
    final toolName = normalizeText(item['name']);
    final arguments = decodeToolArguments(item['arguments']);
    if (toolName == null || arguments == null) {
      return null;
    }

    return PlannerToolChoice.callTool(
      toolName: toolName,
      arguments: arguments,
    );
  }

  String? _extractMessageText(Map<String, dynamic> item) {
    final content = item['content'];
    if (content is! List) {
      return null;
    }

    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) {
        continue;
      }
      final normalizedPart = part.cast<String, dynamic>();
      if (normalizedPart['type'] != 'output_text') {
        continue;
      }
      final text = normalizeText(normalizedPart['text']);
      if (text != null) {
        buffer.write(text);
      }
    }

    final aggregated = buffer.toString().trim();
    if (aggregated.isEmpty) {
      return null;
    }
    return aggregated;
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
  Map<String, dynamic> buildPlannerPayloadFromCarriers({
    required List<PlannerContextCarrier> carriers,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
  }) {
    throw UnimplementedError('Task 14 implements this');
  }
}
