import 'dart:convert';

import 'package:openai_dart/openai_dart.dart' as oai;

import '../../../services/chat_service.dart';
import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';
import '../../agent/planner_tool_choice.dart';
import '../../agent/planner_tool_option.dart';
import '../../chat_message.dart';
import '../../context/planner_context_carrier.dart';
import '../llm_config.dart';
import '../llm_request_options.dart';
import '../streaming_decision_accumulator.dart';
import 'adapter_utils.dart';
import 'api_style_adapter.dart';
import '../api_protocol_resolver.dart';
import 'sdk_message_converter.dart';

/// SDK-backed implementation of [ApiStyleAdapter] for the Chat Completions
/// protocol, powered by `openai_dart`.
///
/// This adapter uses the `openai_dart` package to build correct request
/// payloads and parse responses, avoiding manual JSON construction that
/// can miss provider-specific requirements (e.g., DeepSeek's strict
/// tool_calls message sequencing).
class SdkChatCompletionsAdapter extends ApiStyleAdapter {
  const SdkChatCompletionsAdapter({
    SdkMessageConverter? messageConverter,
  }) : _messageConverter = messageConverter ?? const SdkMessageConverter();

  final SdkMessageConverter _messageConverter;

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
      messages,
      config.systemPrompt,
    );
    final sdkMessages = _messageConverter.convert(normalizedMessages);

    final request = oai.ChatCompletionCreateRequest(
      model: modelName,
      messages: sdkMessages,
      maxCompletionTokens: requestOptions.maxOutputTokens,
    );

    // Serialize via toJson and strip null fields for clean payload
    return _cleanNulls(request.toJson());
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
    final normalizedMessages = normalizeMessagesWithConfiguredSystemPrompt(
      messages,
      config.systemPrompt,
    );
    final sdkMessages = _messageConverter.convert(normalizedMessages);

    final tools = availableTools
        .map(
          (tool) => oai.Tool.function(
            name: tool.name,
            description: tool.description,
            parameters: tool.inputSchema,
          ),
        )
        .toList(growable: false);

    final includeParallel = tools.isNotEmpty && !_isDeepSeekModel(modelName);
    final request = oai.ChatCompletionCreateRequest(
      model: modelName,
      messages: sdkMessages,
      maxCompletionTokens: requestOptions.maxOutputTokens,
      tools: tools.isNotEmpty ? tools : null,
      toolChoice: tools.isNotEmpty ? oai.ToolChoice.auto() : null,
      parallelToolCalls: includeParallel ? parallelToolCalls : null,
    );

    return _cleanNulls(request.toJson());
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
  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
    try {
      final completion = oai.ChatCompletion.fromJson(payload);
      final message = completion.choices.firstOrNull?.message;
      if (message == null) return null;

      final toolCalls = <ModelToolCall>[];
      if (message.hasToolCalls) {
        for (var i = 0; i < message.toolCalls!.length; i++) {
          final tc = message.toolCalls![i];
          final args = _decodeArguments(tc.function.arguments);
          if (args != null) {
            toolCalls.add(
              ModelToolCall(
                providerCallId: tc.id,
                toolName: tc.function.name,
                arguments: args,
                sequence: i,
              ),
            );
          }
        }
      }

      final content = message.content?.trim();
      final reasoning = message.reasoningContent?.trim() ??
          message.reasoning?.trim();

      if (toolCalls.isEmpty &&
          (content == null || content.isEmpty) &&
          (reasoning == null || reasoning.isEmpty)) {
        return null;
      }

      return ModelTurnDecision(
        toolCalls: toolCalls,
        assistantMessage: content?.isEmpty == true ? null : content,
        visibleReasoning: reasoning?.isEmpty == true ? null : reasoning,
        providerState: {
          if (completion.id != null) 'response_id': completion.id,
        },
        isTerminal: toolCalls.isEmpty,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, dynamic>? extractRawAssistantMessage(
    Map<String, dynamic> responsePayload,
  ) {
    throw UnimplementedError('Task 7 implements this');
  }

  @override
  Map<String, dynamic>? assembleRawFromStreamingSnapshot(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    throw UnimplementedError('Task 7 implements this');
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
    throw UnimplementedError('Task 12 implements this');
  }

  bool _isDeepSeekModel(String modelName) {
    return modelName.trim().toLowerCase().startsWith('deepseek');
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

  /// Strip null values from a JSON map for cleaner request payloads.
  /// The SDK includes null fields; some providers reject unexpected keys.
  Map<String, dynamic> _cleanNulls(Map<String, dynamic> json) {
    final cleaned = <String, dynamic>{};
    for (final entry in json.entries) {
      if (entry.value == null) continue;
      if (entry.value is Map) {
        cleaned[entry.key] = _cleanNulls(
          Map<String, dynamic>.from(entry.value as Map),
        );
      } else if (entry.value is List) {
        cleaned[entry.key] = (entry.value as List).map((item) {
          if (item is Map) return _cleanNulls(Map<String, dynamic>.from(item));
          return item;
        }).toList();
      } else {
        cleaned[entry.key] = entry.value;
      }
    }
    return cleaned;
  }
}
