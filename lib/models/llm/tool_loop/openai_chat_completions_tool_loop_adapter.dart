import 'dart:convert';

import '../../agent/model_tool_call.dart';
import '../../agent/model_turn_decision.dart';

class OpenAIChatCompletionsToolLoopAdapter {
  const OpenAIChatCompletionsToolLoopAdapter();

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
    final toolCalls = _parseToolCalls(normalizedMessage);
    final contentParts = _extractContentParts(normalizedMessage['content']);
    final content = contentParts.content;
    final visibleReasoning = _joinReasoningParts([
      normalizedMessage['reasoning_content'],
      normalizedMessage['reasoning'],
      normalizedMessage['thinking'],
      contentParts.reasoning,
    ]);
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

  _ContentParts _extractContentParts(dynamic content) {
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final inlineText = _normalizeText(content);
    if (inlineText != null) {
      final extracted = _extractThinkEnvelope(inlineText);
      if (extracted.reasoning != null) {
        reasoningBuffer.write(extracted.reasoning);
      }
      if (extracted.content != null) {
        textBuffer.write(extracted.content);
      }
      return _ContentParts(
        content: _normalizeText(textBuffer.toString()),
        reasoning: _normalizeText(reasoningBuffer.toString()),
      );
    }
    if (content is List) {
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final text =
            _normalizeText(normalizedItem['text'] ?? normalizedItem['content']);
        if (text != null) {
          final extracted = _extractThinkEnvelope(text);
          if (extracted.reasoning != null) {
            reasoningBuffer.write(extracted.reasoning);
          }
          if (extracted.content != null) {
            textBuffer.write(extracted.content);
          }
        }
      }
    }
    return _ContentParts(
      content: _normalizeText(textBuffer.toString()),
      reasoning: _normalizeText(reasoningBuffer.toString()),
    );
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

  String? _joinReasoningParts(List<dynamic> values) {
    final buffer = StringBuffer();
    for (final value in values) {
      final text = _normalizeText(value);
      if (text != null) {
        buffer.write(text);
      }
    }
    return _normalizeText(buffer.toString());
  }

  _ContentParts _extractThinkEnvelope(String value) {
    final matches = _thinkTagPattern.allMatches(value).toList(growable: false);
    if (matches.isEmpty) {
      return _ContentParts(content: value);
    }

    final reasoningBuffer = StringBuffer();
    for (final match in matches) {
      final inner = _normalizeText(match.group(1));
      if (inner != null) {
        reasoningBuffer.write(inner);
      }
    }
    final stripped = value.replaceAll(_thinkTagPattern, '').trim();
    return _ContentParts(
      content: _normalizeText(stripped),
      reasoning: _normalizeText(reasoningBuffer.toString()),
    );
  }

  static final RegExp _thinkTagPattern = RegExp(
    r'<think>([\s\S]*?)</think>',
    caseSensitive: false,
  );
}

class _ContentParts {
  const _ContentParts({this.content, this.reasoning});

  final String? content;
  final String? reasoning;
}
