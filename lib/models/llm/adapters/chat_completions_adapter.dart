import 'dart:convert';

import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../llm_request_options.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';

/// Adapter for the OpenAI-compatible Chat Completions protocol.
class ChatCompletionsAdapter extends ApiStyleAdapter {
  const ChatCompletionsAdapter();

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
    return {
      'model': modelName,
      'messages': normalizedMessages
          .map(
            (msg) => _buildMessage(msg),
          )
          .toList(),
      'stream': stream,
    };
  }

  @override
  Map<String, dynamic> buildPlannerPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    LlmRequestOptions requestOptions = const LlmRequestOptions(),
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems = const [],
    Map<String, dynamic>? providerState,
  }) {
    final payload = buildChatPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: false,
      requestOptions: requestOptions,
    );
    final payloadMessages = List<Map<String, dynamic>>.from(
      (payload['messages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)),
    );
    if (continuationItems.isNotEmpty) {
      payload['messages'] = [
        ...payloadMessages,
        ..._buildContinuationMessages(continuationItems),
      ];
    }
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
      payload['parallel_tool_calls'] = parallelToolCalls;
    }
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

  List<Map<String, dynamic>> _buildContinuationMessages(
    List<Map<String, dynamic>> continuationItems,
  ) {
    final messages = <Map<String, dynamic>>[];
    for (final rawItem in continuationItems) {
      final item = Map<String, dynamic>.from(rawItem);
      final type = item['type'];
      if (type == 'assistant_tool_call') {
        final toolCallId = normalizeText(item['toolCallId']);
        final toolName = normalizeText(item['toolName']);
        final arguments = item['arguments'];
        if (toolCallId == null || toolName == null || arguments is! Map) {
          continue;
        }
        messages.add({
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': toolCallId,
              'type': 'function',
              'function': {
                'name': toolName,
                'arguments': jsonEncode(arguments),
              },
            },
          ],
        });
        continue;
      }
      if (type == 'tool_result') {
        final toolCallId = normalizeText(item['toolCallId']);
        final output = normalizeText(item['output']);
        if (toolCallId == null || output == null) {
          continue;
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': output,
        });
        continue;
      }
      if (type == 'user_interaction_answer') {
        final content = normalizeText(item['content']);
        if (content == null) {
          continue;
        }
        messages.add({
          'role': 'user',
          'content': content,
        });
      }
    }
    return messages;
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
}
