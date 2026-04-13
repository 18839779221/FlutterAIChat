import 'dart:convert';

import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';

class OpenAIChatCompletionsToolLoopAdapter {
  const OpenAIChatCompletionsToolLoopAdapter();

  ModelTurnDecision? parseDecision(Map<String, dynamic> payload) {
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
    final toolCalls = _parseToolCalls(normalizedMessage);
    if (toolCalls.isNotEmpty) {
      return ModelTurnDecision(
        toolCalls: toolCalls,
        assistantMessage: null,
        providerState: const {},
        isTerminal: false,
      );
    }

    final content = _extractMessageText(normalizedMessage);
    if (content == null) {
      return null;
    }

    return ModelTurnDecision(
      toolCalls: const [],
      assistantMessage: content,
      providerState: const {},
      isTerminal: true,
    );
  }

  List<ModelToolCall> _parseToolCalls(Map<String, dynamic> message) {
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List || toolCalls.isEmpty) {
      return const [];
    }

    final parsed = <ModelToolCall>[];
    for (var i = 0; i < toolCalls.length; i++) {
      final rawToolCall = toolCalls[i];
      if (rawToolCall is! Map) {
        continue;
      }
      final function = rawToolCall['function'];
      if (function is! Map) {
        continue;
      }
      final toolName = _normalizeText(function['name']);
      final arguments = _decodeArguments(function['arguments']);
      if (toolName == null || arguments == null) {
        continue;
      }
      parsed.add(
        ModelToolCall(
          providerCallId: _normalizeText(rawToolCall['id']),
          toolName: toolName,
          arguments: arguments,
          sequence: i,
        ),
      );
    }
    return parsed;
  }

  String? _extractMessageText(Map<String, dynamic> message) {
    final content = message['content'];
    final inlineText = _normalizeText(content);
    if (inlineText != null) {
      return inlineText;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final text =
            _normalizeText(normalizedItem['text'] ?? normalizedItem['content']);
        if (text != null) {
          buffer.write(text);
        }
      }
      final aggregated = buffer.toString().trim();
      if (aggregated.isNotEmpty) {
        return aggregated;
      }
    }
    return null;
  }

  Map<String, dynamic>? _decodeArguments(dynamic rawArguments) {
    if (rawArguments is Map) {
      return rawArguments.cast<String, dynamic>();
    }
    final encoded = _normalizeText(rawArguments);
    if (encoded == null) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return null;
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
