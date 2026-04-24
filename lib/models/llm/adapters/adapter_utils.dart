import 'dart:convert';

import '../../chat_message.dart';

/// Shared helpers for [ApiStyleAdapter] implementations.
///
/// These were originally private members of `ConfigurableHttpLLM`.
const String modelContextTypeKey = 'modelContextType';
const String assistantToolUseContextType = 'assistantToolUse';
const String userToolResultContextType = 'userToolResult';

String? normalizeText(dynamic value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

Map<String, dynamic>? decodeToolArguments(dynamic rawArguments) {
  if (rawArguments is Map) {
    return rawArguments.cast<String, dynamic>();
  }

  final encoded = normalizeText(rawArguments);
  if (encoded == null) {
    return null;
  }

  final decoded = jsonDecode(encoded);
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }

  return null;
}

String? modelContextTypeOf(ChatMessage message) {
  final payload = message.payloadJson;
  if (payload == null) {
    return null;
  }
  return normalizeText(payload[modelContextTypeKey]);
}

String? toolNameOf(ChatMessage message) {
  final payload = message.payloadJson;
  if (payload == null) {
    return null;
  }
  return normalizeText(payload['toolName']);
}

Map<String, dynamic>? toolArgumentsOf(ChatMessage message) {
  final payload = message.payloadJson;
  if (payload == null) {
    return null;
  }
  return decodeToolArguments(payload['arguments']);
}

/// Inject the configured system prompt at the front if not already present.
List<ChatMessage> normalizeMessagesWithConfiguredSystemPrompt(
  List<ChatMessage> messages,
  String configuredSystemPrompt,
) {
  final normalizedMessages =
      messages.where((msg) => msg.text.trim().isNotEmpty).toList();
  final trimmed = configuredSystemPrompt.trim();
  if (trimmed.isEmpty) {
    return normalizedMessages;
  }

  final alreadyPresent = normalizedMessages.any(
    (message) =>
        message.role == MessageRole.system &&
        message.text.trim() == trimmed,
  );
  if (alreadyPresent) {
    return normalizedMessages;
  }

  return [
    ChatMessage(
      text: trimmed,
      role: MessageRole.system,
    ),
    ...normalizedMessages,
  ];
}
