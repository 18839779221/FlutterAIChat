import 'dart:convert';

import 'package:openai_dart/openai_dart.dart' as oai;

import '../../../services/chat_service.dart';
import '../../chat_message.dart';
import '../adapters/adapter_utils.dart';

/// Converts our [ChatMessage] model (with `payloadJson` metadata) to
/// `openai_dart` [oai.ChatMessage] instances.
///
/// Key responsibility: merge adjacent assistant text + assistant tool_use
/// messages into a single `ChatMessage.assistant(content, toolCalls)` —
/// this is required by DeepSeek and other strict providers.
class SdkMessageConverter {
  const SdkMessageConverter();

  /// Convert and merge messages for the OpenAI Chat Completions API.
  ///
  /// Handles:
  /// - system / user / assistant role mapping
  /// - assistantToolUse → assistant with toolCalls
  /// - userToolResult → tool message with toolCallId
  /// - Merging adjacent assistant text + toolUse into single message
  /// - Filtering empty messages
  List<oai.ChatMessage> convert(List<ChatMessage> messages) {
    final converted = <oai.ChatMessage>[];
    var i = 0;
    while (i < messages.length) {
      final current = messages[i];
      final next = i + 1 < messages.length ? messages[i + 1] : null;

      // Merge: assistantPlannerMessage + assistantToolUse → single assistant
      if (next != null &&
          _isAssistantPlainText(current) &&
          _isAssistantToolUse(next)) {
        final merged = _mergeAssistantWithToolUse(current, next);
        if (merged != null) {
          converted.add(merged);
        }
        i += 2;
        continue;
      }

      final single = _convertSingle(current);
      if (single != null) {
        converted.add(single);
      }
      i += 1;
    }
    return converted;
  }

  /// Convert messages to SDK format and serialize to JSON list
  /// (convenience for building request payloads).
  List<Map<String, dynamic>> convertToJson(List<ChatMessage> messages) {
    return convert(messages)
        .map((msg) => msg.toJson())
        .toList(growable: false);
  }

  // --- Private helpers ---

  oai.ChatMessage? _convertSingle(ChatMessage message) {
    final contextType = modelContextTypeOf(message);

    if (contextType == assistantToolUseContextType) {
      return _convertToolUse(message);
    }
    if (contextType == userToolResultContextType) {
      return _convertToolResult(message);
    }

    final text = message.text.trim();
    if (text.isEmpty) {
      return null;
    }

    switch (message.role) {
      case MessageRole.system:
        return oai.ChatMessage.system(text);
      case MessageRole.user:
        return oai.ChatMessage.user(text);
      case MessageRole.assistant:
        return oai.ChatMessage.assistant(content: text);
    }
  }

  oai.ChatMessage? _convertToolUse(ChatMessage message) {
    final toolName = toolNameOf(message);
    final providerCallId = providerCallIdOf(message);
    if (toolName == null || providerCallId == null) {
      // Fallback: treat as plain assistant text
      final text = message.text.trim();
      if (text.isEmpty) return null;
      return oai.ChatMessage.assistant(content: text);
    }

    final arguments = toolArgumentsOf(message) ?? const <String, dynamic>{};
    return oai.ChatMessage.assistant(
      content: message.text.trim().isEmpty ? null : message.text.trim(),
      toolCalls: [
        oai.ToolCall(
          id: providerCallId,
          type: 'function',
          function: oai.FunctionCall(
            name: toolName,
            arguments: jsonEncode(arguments),
          ),
        ),
      ],
    );
  }

  oai.ChatMessage? _convertToolResult(ChatMessage message) {
    final providerCallId = providerCallIdOf(message);
    if (providerCallId == null) {
      // Fallback: treat as user message
      final text = message.text.trim();
      if (text.isEmpty) return null;
      return oai.ChatMessage.user(text);
    }

    return oai.ChatMessage.tool(
      toolCallId: providerCallId,
      content: message.text,
    );
  }

  /// Merge an assistant text message with the following assistant tool_use
  /// message into a single assistant message with both content and toolCalls.
  oai.ChatMessage? _mergeAssistantWithToolUse(
    ChatMessage textMessage,
    ChatMessage toolUseMessage,
  ) {
    final toolName = toolNameOf(toolUseMessage);
    final providerCallId = providerCallIdOf(toolUseMessage);

    if (toolName == null || providerCallId == null) {
      // Can't merge — convert each separately
      final first = _convertSingle(textMessage);
      // Return only the first; caller will skip toolUseMessage
      return first;
    }

    final arguments =
        toolArgumentsOf(toolUseMessage) ?? const <String, dynamic>{};
    final content = textMessage.text.trim();

    return oai.ChatMessage.assistant(
      content: content.isEmpty ? null : content,
      toolCalls: [
        oai.ToolCall(
          id: providerCallId,
          type: 'function',
          function: oai.FunctionCall(
            name: toolName,
            arguments: jsonEncode(arguments),
          ),
        ),
      ],
    );
  }

  bool _isAssistantPlainText(ChatMessage message) {
    return message.role == MessageRole.assistant &&
        modelContextTypeOf(message) != assistantToolUseContextType &&
        modelContextTypeOf(message) != userToolResultContextType;
  }

  bool _isAssistantToolUse(ChatMessage message) {
    return modelContextTypeOf(message) == assistantToolUseContextType;
  }
}
