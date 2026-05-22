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

/// Adapter for the Anthropic Messages protocol.
class AnthropicMessagesAdapter extends ApiStyleAdapter {
  const AnthropicMessagesAdapter();

  @override
  ApiStyle get style => ApiStyle.anthropicMessages;

  @override
  Map<String, String> buildHeaders(LLMConfig runtimeConfig) {
    return {
      'Content-Type': 'application/json',
      'x-api-key': runtimeConfig.apiKey,
      'anthropic-version': '2023-06-01',
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
    return _buildMessagesPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: stream,
      requestOptions: requestOptions,
    );
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
    final payload = _buildMessagesPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: false,
      requestOptions: requestOptions,
    );
    final tools = availableTools
        .map(
          (tool) => {
            'name': tool.name,
            'description': tool.description,
            'input_schema': tool.inputSchema,
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = {'type': 'auto'};
    }
    _applyCacheHints(payload, requestOptions.cache);
    return payload;
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

    return {
      'model': modelName,
      if (systemSegments.isNotEmpty) 'system': systemSegments.join('\n\n'),
      'messages': normalizedMessages,
      'stream': stream,
      if (requestOptions.maxOutputTokens != null)
        'max_tokens': requestOptions.maxOutputTokens,
      if (!requestOptions.allowReasoning)
        'thinking': const {'type': 'disabled'},
    };
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
              'content': message.text,
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

    for (final carrier in carriers) {
      switch (carrier) {
        case SyntheticCarrier(role: SyntheticRole.system, :final content):
          systemText = systemText == null ? content : '$systemText\n\n$content';

        case SyntheticCarrier(role: SyntheticRole.user, :final content):
          messages.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': content},
            ],
          });

        case SyntheticCarrier(
              role: SyntheticRole.toolResult,
              :final toolCallId,
              :final content,
            ):
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': toolCallId,
                'content': content,
              },
            ],
          });

        case RawAssistantCarrier(:final rawJson):
          messages.add(Map<String, dynamic>.from(rawJson));
      }
    }

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
    };
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
