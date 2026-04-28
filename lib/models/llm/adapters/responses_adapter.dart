import 'dart:convert';

import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../../../services/chat_service.dart';
import '../api_protocol_resolver.dart';
import '../llm_config.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';
import 'historical_tool_transcript_state.dart';

/// Adapter for the OpenAI Responses protocol.
class ResponsesAdapter extends ApiStyleAdapter {
  const ResponsesAdapter();

  static const String _transcriptIdPrefix = 'fc_ctx_';
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
  }) {
    final normalizedMessages = normalizeMessagesWithConfiguredSystemPrompt(
        messages, config.systemPrompt);
    final transcriptState = HistoricalToolTranscriptState(_transcriptIdPrefix);
    return {
      'model': modelName,
      'input': normalizedMessages
          .map(
            (msg) => _buildInputItem(
              msg,
              transcriptState: transcriptState,
            ),
          )
          .toList(),
      'reasoning': _reasoningConfig,
      'stream': stream,
      'store': false,
    };
  }

  @override
  Map<String, dynamic> buildPlannerPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems = const [],
    Map<String, dynamic>? providerState,
  }) {
    final payload = buildChatPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      stream: false,
    );
    // Responses tool-loop continuation relies on previous_response_id, so the
    // planner response must remain server-addressable instead of being forced
    // into stateless store:false mode.
    payload['store'] = true;
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
    if (previousResponseId != null && previousResponseId.isNotEmpty) {
      payload['previous_response_id'] = previousResponseId;
    }
    if (continuationItems.isNotEmpty) {
      final continuationInputItems =
          _buildContinuationInputItems(
        continuationItems,
        includeAssistantToolCalls:
            previousResponseId == null || previousResponseId.isEmpty,
      );
      final useContinuationOnly = previousResponseId != null &&
          previousResponseId.isNotEmpty &&
          continuationInputItems.isNotEmpty;
      final input = useContinuationOnly
          ? <dynamic>[]
          : List<dynamic>.from(
              payload['input'] as List<dynamic>? ?? const <dynamic>[],
            );
      for (final item in continuationInputItems) {
        input.add(Map<String, dynamic>.from(item));
      }
      payload['input'] = input;
    }
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

  Map<String, dynamic> _buildInputItem(
    ChatMessage message, {
    required HistoricalToolTranscriptState transcriptState,
  }) {
    final contextType = modelContextTypeOf(message);
    if (contextType == assistantToolUseContextType) {
      final toolName = toolNameOf(message);
      if (toolName != null) {
        final callId = transcriptState.register(toolName);
        return {
          'type': 'function_call',
          'call_id': callId,
          'name': toolName,
          'arguments': jsonEncode(toolArgumentsOf(message) ?? const {}),
        };
      }
    }
    if (contextType == userToolResultContextType) {
      final invocation = transcriptState.consume(
        preferredToolName: toolNameOf(message),
      );
      if (invocation != null) {
        return {
          'type': 'function_call_output',
          'call_id': invocation.id,
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

  List<Map<String, dynamic>> _buildContinuationInputItems(
    List<Map<String, dynamic>> continuationItems,
    {
    required bool includeAssistantToolCalls,
  }) {
    final items = <Map<String, dynamic>>[];
    for (final item in continuationItems) {
      final type = item['type'];
      if (type == 'user_interaction_answer') {
        final content = normalizeText(item['content']);
        if (content == null) {
          continue;
        }
        items.add({
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': content,
            },
          ],
        });
        continue;
      }
      if (type == 'assistant_tool_call') {
        if (!includeAssistantToolCalls) {
          continue;
        }
        final callId = normalizeText(item['toolCallId']);
        final toolName = normalizeText(item['toolName']);
        final arguments = item['arguments'];
        if (callId == null || toolName == null || arguments is! Map) {
          continue;
        }
        items.add({
          'type': 'function_call',
          'call_id': callId,
          'name': toolName,
          'arguments': jsonEncode(arguments),
        });
        continue;
      }
      if (type == 'tool_result') {
        final callId = normalizeText(item['toolCallId']);
        final output = normalizeText(item['output']);
        if (callId == null || output == null) {
          continue;
        }
        items.add({
          'type': 'function_call_output',
          'call_id': callId,
          'output': output,
        });
        continue;
      }
      items.add(Map<String, dynamic>.from(item));
    }
    return items;
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
}
